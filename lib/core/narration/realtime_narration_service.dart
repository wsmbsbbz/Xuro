import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:xuro/core/audio/events/playback_event_hub.dart';
import 'package:xuro/core/audio/models/subtitle.dart';
import 'package:xuro/core/narration/models/narration_segment.dart';
import 'package:xuro/core/narration/narration_clip_player.dart';
import 'package:xuro/core/narration/tts/tts_provider.dart';
import 'package:xuro/core/narration/tts_clip_cache.dart';
import 'package:xuro/core/settings/app_settings_service.dart';
import 'package:xuro/data/repositories/auth_repository.dart';
import 'package:xuro/utils/logger.dart';

enum NarrationRuntimeStatus {
  unavailable,
  idle,
  preparing,
  ready,
  playing,
  failed,
}

class RealtimeNarrationService extends ChangeNotifier {
  static const _preloadWindow = Duration(seconds: 45);
  static const _seekJumpThreshold = Duration(milliseconds: 1500);

  final PlaybackEventHub _eventHub;
  final AppSettingsService _settings;
  final TtsProvider _ttsProvider;
  final TtsClipCache _clipCache;
  final NarrationClipPlayer _clipPlayer;
  final AuthRepository _authRepository;

  final List<StreamSubscription> _subscriptions = [];
  final Map<String, Future<void>> _generationTasks = {};

  List<NarrationSegment> _segments = [];
  NarrationRuntimeStatus _status = NarrationRuntimeStatus.unavailable;
  String? _message;
  String? _lastPlayedText;
  String? _lastPlayedSegmentId;
  Duration? _lastPosition;
  bool _mainPlaying = false;
  int _generationToken = 0;
  Timer? _manifestTimer;
  String? _remoteSessionId;
  Dio? _remoteDio;

  RealtimeNarrationService({
    required PlaybackEventHub eventHub,
    required AppSettingsService settings,
    required TtsProvider ttsProvider,
    required TtsClipCache clipCache,
    required NarrationClipPlayer clipPlayer,
    required AuthRepository authRepository,
  })  : _eventHub = eventHub,
        _settings = settings,
        _ttsProvider = ttsProvider,
        _clipCache = clipCache,
        _clipPlayer = clipPlayer,
        _authRepository = authRepository {
    _settings.addListener(_onSettingsChanged);
    _subscriptions.addAll([
      _eventHub.playbackState.listen(_onPlaybackState),
      _eventHub.playbackProgress.listen((event) => _onProgress(event.position)),
      _eventHub.contextChange.listen((_) => reset()),
      _eventHub.playbackCleared.listen((_) => reset()),
      _eventHub.playbackCompleted.listen((_) => _clipPlayer.stop()),
    ]);
    _setStatus(
      _settings.narrationEnabled
          ? NarrationRuntimeStatus.idle
          : NarrationRuntimeStatus.unavailable,
    );
  }

  NarrationRuntimeStatus get status => _status;
  String? get message => _message;
  bool get hasSegments => _segments.isNotEmpty;
  bool get isAvailable => _ttsProvider.isAvailable;
  String? get lastPlayedText => _lastPlayedText;
  int get totalCount => _segments.length;
  int get pendingCount => _countByStatus(NarrationSegmentStatus.pending);
  int get generatingCount => _countByStatus(NarrationSegmentStatus.generating);
  int get readyCount => _countByStatus(NarrationSegmentStatus.ready);
  int get failedCount => _countByStatus(NarrationSegmentStatus.failed);

  void prepare(SubtitleList? subtitleList, {String? audioUrl}) {
    _generationToken++;
    _generationTasks.clear();
    _lastPlayedSegmentId = null;
    _lastPosition = null;
    _lastPlayedText = null;
    _remoteSessionId = null;
    _manifestTimer?.cancel();

    if (!_settings.narrationEnabled) {
      _segments = [];
      _setStatus(NarrationRuntimeStatus.unavailable);
      return;
    }

    if (subtitleList == null || subtitleList.subtitles.isEmpty) {
      _segments = [];
      _setStatus(NarrationRuntimeStatus.unavailable, '未找到可用于旁白的字幕');
      return;
    }

    _segments = NarrationSegment.fromSubtitleList(subtitleList);
    AppLogger.info('实时旁白已准备: segments=${_segments.length}');

    if (_settings.narrationBackendUrl.isNotEmpty) {
      if (audioUrl == null || audioUrl.isEmpty) {
        _setStatus(NarrationRuntimeStatus.failed, '旁白后端需要当前音频 URL');
        return;
      }
      _setStatus(NarrationRuntimeStatus.preparing, '正在创建 tts-ijc Edge 旁白会话');
      unawaited(_startRemoteSession(subtitleList, audioUrl, _generationToken));
      return;
    }

    if (!_ttsProvider.isAvailable) {
      _segments = [];
      _setStatus(NarrationRuntimeStatus.failed, '当前平台暂不支持本机旁白生成');
      return;
    }

    _setStatus(
      _segments.isEmpty
          ? NarrationRuntimeStatus.unavailable
          : NarrationRuntimeStatus.ready,
    );
  }

  Future<void> reset() async {
    _generationToken++;
    _generationTasks.clear();
    _segments = [];
    _lastPlayedSegmentId = null;
    _lastPosition = null;
    _lastPlayedText = null;
    _remoteSessionId = null;
    _manifestTimer?.cancel();
    await _clipPlayer.stop();
    _setStatus(
      _settings.narrationEnabled
          ? NarrationRuntimeStatus.idle
          : NarrationRuntimeStatus.unavailable,
    );
  }

  Future<void> disposeService() async {
    _settings.removeListener(_onSettingsChanged);
    _manifestTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _clipPlayer.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!_settings.narrationEnabled) {
      reset();
      return;
    }
    _remoteDio = null;
    if (_segments.isEmpty) {
      _setStatus(NarrationRuntimeStatus.idle);
    }
  }

  void _onPlaybackState(event) {
    _mainPlaying = event.state.playing &&
        event.state.processingState != ProcessingState.completed;
    if (!_mainPlaying) {
      _clipPlayer.stop();
      if (_status == NarrationRuntimeStatus.playing) {
        _setStatus(NarrationRuntimeStatus.ready);
      }
    }
  }

  void _onProgress(Duration position) {
    if (!_settings.narrationEnabled ||
        !_mainPlaying ||
        _segments.isEmpty ||
        !_ttsProvider.isAvailable) {
      return;
    }

    final previous = _lastPosition;
    _lastPosition = position;
    if (previous != null &&
        _absoluteDuration(position - previous) > _seekJumpThreshold) {
      _lastPlayedSegmentId = null;
      unawaited(_clipPlayer.stop());
    }

    if (_remoteSessionId == null) {
      _preloadAround(position);
    }
    _playCurrentIfReady(position);
  }

  Future<void> _startRemoteSession(
    SubtitleList subtitleList,
    String audioUrl,
    int token,
  ) async {
    try {
      final dio = await _dioForRemoteBackend();
      final resp = await dio.post<Map<String, dynamic>>(
        '/narration/sessions',
        data: {
          'audio_url': audioUrl,
          'vtt_text': _subtitleListToVtt(subtitleList),
          'tts_provider': 'edge',
          'voice': _edgeVoiceFor(_settings.narrationVoice),
          'speedup': true,
          'filter_onomatopoeia': false,
          'concurrency': _settings.narrationConcurrency,
        },
      );
      if (token != _generationToken) return;
      _remoteSessionId = resp.data?['session_id'] as String?;
      if (_remoteSessionId == null || _remoteSessionId!.isEmpty) {
        throw Exception('tts-ijc 未返回 session_id');
      }
      AppLogger.info('tts-ijc 旁白会话已创建: $_remoteSessionId');
      _setStatus(
          NarrationRuntimeStatus.preparing, 'tts-ijc 已接收队列，等待 Edge TTS 片段');
      await _pollRemoteManifest(token);
      _manifestTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_pollRemoteManifest(token)),
      );
    } catch (e, stack) {
      AppLogger.error('创建 tts-ijc 旁白会话失败', e, stack);
      if (token != _generationToken) return;
      _setStatus(NarrationRuntimeStatus.failed, 'tts-ijc 旁白会话失败: $e');
    }
  }

  Future<void> _pollRemoteManifest(int token) async {
    final sessionId = _remoteSessionId;
    if (sessionId == null || token != _generationToken) return;
    try {
      final dio = await _dioForRemoteBackend();
      final resp = await dio.get<Map<String, dynamic>>(
        '/narration/sessions/$sessionId/manifest',
      );
      if (token != _generationToken) return;
      final data = resp.data ?? {};
      final rawSegments = data['segments'];
      if (rawSegments is List) {
        _segments = rawSegments
            .whereType<Map>()
            .map((raw) => _segmentFromManifest(raw.cast<String, dynamic>()))
            .toList(growable: false);
      }
      final status = data['status']?.toString() ?? 'processing';
      final nextStatus = switch (status) {
        'ready' => NarrationRuntimeStatus.ready,
        'partial_failed' => NarrationRuntimeStatus.ready,
        'failed' => NarrationRuntimeStatus.failed,
        _ => NarrationRuntimeStatus.preparing,
      };
      _setStatus(
        nextStatus,
        'tts-ijc: $status，ready $readyCount/$totalCount，failed $failedCount',
      );
      final position = _lastPosition;
      if (_mainPlaying && position != null) {
        _playCurrentIfReady(position, allowReplay: true);
      }
      if (status == 'ready' ||
          status == 'partial_failed' ||
          status == 'failed') {
        _manifestTimer?.cancel();
      }
    } catch (e, stack) {
      AppLogger.error('轮询 tts-ijc 旁白 manifest 失败', e, stack);
      if (token != _generationToken) return;
      _setStatus(NarrationRuntimeStatus.failed, '轮询 tts-ijc 失败: $e');
    }
  }

  void _preloadAround(Duration position) {
    final token = _generationToken;
    final candidates = _segments.where((segment) {
      return segment.contains(position) ||
          segment.startsInWindow(position, _preloadWindow);
    });
    for (final segment in candidates) {
      if (segment.status == NarrationSegmentStatus.ready ||
          segment.status == NarrationSegmentStatus.generating ||
          segment.status == NarrationSegmentStatus.failed ||
          _generationTasks.containsKey(segment.id)) {
        continue;
      }
      final task = _generateSegment(segment, token);
      _generationTasks[segment.id] = task;
      task.whenComplete(() => _generationTasks.remove(segment.id));
      if (_generationTasks.length >= _settings.narrationConcurrency) {
        break;
      }
    }
  }

  Future<void> _generateSegment(NarrationSegment segment, int token) async {
    if (token != _generationToken) return;
    segment.status = NarrationSegmentStatus.generating;
    _setStatus(
      NarrationRuntimeStatus.preparing,
      '正在生成旁白 ${readyCount + generatingCount + 1}/$totalCount',
    );
    try {
      final outputPath = await _clipCache.pathFor(
        provider: _ttsProvider.id,
        voice: _settings.narrationVoice,
        text: segment.text,
        extension: _ttsProvider.id == 'edge_online' ? 'mp3' : 'wav',
      );
      if (!await _clipCache.exists(outputPath)) {
        AppLogger.debug('开始生成旁白片段: ${segment.index} ${segment.text}');
        await _ttsProvider.synthesizeToFile(
          text: segment.text,
          outputPath: outputPath,
          voice: _settings.narrationVoice,
        );
      } else {
        AppLogger.debug('命中旁白缓存: ${segment.index}');
      }
      if (token != _generationToken) return;
      segment
        ..audioPath = outputPath
        ..status = NarrationSegmentStatus.ready
        ..error = null;
      _setStatus(NarrationRuntimeStatus.ready, '旁白已就绪 $readyCount/$totalCount');
      unawaited(_clipCache.cleanupIfNeeded());
      final position = _lastPosition;
      if (_mainPlaying && position != null && segment.contains(position)) {
        _playCurrentIfReady(position, allowReplay: true);
      }
    } catch (e, stack) {
      AppLogger.error('生成旁白片段失败', e, stack);
      if (token != _generationToken) return;
      segment
        ..status = NarrationSegmentStatus.failed
        ..error = e.toString();
      _setStatus(NarrationRuntimeStatus.failed, '旁白生成失败，已跳过部分片段');
    }
  }

  void _playCurrentIfReady(Duration position, {bool allowReplay = false}) {
    NarrationSegment? current;
    for (final segment in _segments) {
      if (segment.contains(position)) {
        current = segment;
        break;
      }
    }
    if (current == null) {
      _lastPlayedSegmentId = null;
      return;
    }
    if ((!allowReplay && _lastPlayedSegmentId == current.id) ||
        current.status != NarrationSegmentStatus.ready ||
        current.audioPath == null && current.audioUrl == null) {
      return;
    }
    _lastPlayedSegmentId = current.id;
    _lastPlayedText = current.text;
    AppLogger.info('播放旁白片段: ${current.index} ${current.text}');
    _setStatus(NarrationRuntimeStatus.playing, '正在播放旁白: ${current.text}');
    unawaited(
      (current.audioUrl != null
              ? _clipPlayer.playUrl(
                  current.audioUrl!,
                  volume: _settings.narrationVolume,
                )
              : _clipPlayer.playFile(
                  current.audioPath!,
                  volume: _settings.narrationVolume,
                ))
          .catchError((Object e, StackTrace st) {
        AppLogger.error('旁白播放失败', e, st);
        _setStatus(NarrationRuntimeStatus.failed, '旁白播放失败');
      }),
    );
  }

  Future<Dio> _dioForRemoteBackend() async {
    final baseUrl = _settings.narrationBackendUrl;
    final current = _remoteDio;
    if (current != null && current.options.baseUrl == baseUrl) return current;
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final configuredToken = _settings.narrationBackendToken;
          final token = configuredToken.isNotEmpty
              ? configuredToken
              : (await _authRepository.getAuthData())?.token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
    _remoteDio = dio;
    return dio;
  }

  NarrationSegment _segmentFromManifest(Map<String, dynamic> raw) {
    final statusText = raw['status']?.toString() ?? 'queued';
    return NarrationSegment(
      id: raw['id']?.toString() ?? '${raw['start_ms']}-${raw['end_ms']}',
      index: 0,
      start: Duration(milliseconds: (raw['start_ms'] as num?)?.toInt() ?? 0),
      end: Duration(milliseconds: (raw['end_ms'] as num?)?.toInt() ?? 0),
      text: raw['text']?.toString() ?? '',
      status: switch (statusText) {
        'ready' => NarrationSegmentStatus.ready,
        'failed' => NarrationSegmentStatus.failed,
        'processing' => NarrationSegmentStatus.generating,
        _ => NarrationSegmentStatus.pending,
      },
      audioUrl: raw['audio_url']?.toString().isEmpty == true
          ? null
          : raw['audio_url']?.toString(),
      error: raw['error']?.toString(),
    );
  }

  String _subtitleListToVtt(SubtitleList list) {
    final buffer = StringBuffer('WEBVTT\n\n');
    for (final subtitle in list.subtitles) {
      buffer
        ..write(_formatVttTime(subtitle.start))
        ..write(' --> ')
        ..writeln(_formatVttTime(subtitle.end))
        ..writeln(subtitle.text)
        ..writeln();
    }
    return buffer.toString();
  }

  String _formatVttTime(Duration duration) {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final ms = duration.inMilliseconds.remainder(1000);
    return '${two(hours)}:${two(minutes)}:${two(seconds)}.${three(ms)}';
  }

  String _edgeVoiceFor(String voice) {
    return switch (voice) {
      'zh-TW' => 'zh-TW-HsiaoChenNeural',
      'zh-HK' => 'zh-HK-HiuMaanNeural',
      _ => 'zh-CN-XiaoxiaoNeural',
    };
  }

  void _setStatus(NarrationRuntimeStatus status, [String? message]) {
    _status = status;
    if (message != null) _message = message;
    notifyListeners();
  }

  int _countByStatus(NarrationSegmentStatus status) {
    var count = 0;
    for (final segment in _segments) {
      if (segment.status == status) count++;
    }
    return count;
  }
}

Duration _absoluteDuration(Duration value) {
  return value.isNegative ? -value : value;
}
