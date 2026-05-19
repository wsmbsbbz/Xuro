import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:xuro/core/narration/tts/tts_provider.dart';

class EdgeOnlineTtsProvider implements TtsProvider {
  static const _trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const _chromiumFullVersion = '143.0.3650.75';
  static const _chromiumMajorVersion = '143';
  static const _secMsGecVersion = '1-$_chromiumFullVersion';
  static const _endpoint =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';
  static const _outputFormat = 'audio-24khz-48kbitrate-mono-mp3';
  static const _timeout = Duration(seconds: 45);
  static const _windowsEpochSeconds = 11644473600;
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/$_chromiumMajorVersion.0.0.0 '
      'Safari/537.36 Edg/$_chromiumMajorVersion.0.0.0';

  @override
  String get id => 'edge_online';

  @override
  bool get isAvailable => !kIsWeb;

  @override
  Future<void> synthesizeToFile({
    required String text,
    required String outputPath,
    required String voice,
    double speechRate = 1.0,
  }) async {
    if (!isAvailable) {
      throw UnsupportedError('Edge TTS is not available on web');
    }

    final file = File(outputPath);
    file.parent.createSync(recursive: true);
    if (file.existsSync()) file.deleteSync();

    final connectionId = _connectionId();
    final secMsGec = _generateSecMsGec();
    final httpClient = HttpClient()..userAgent = _userAgent;
    final socket = await WebSocket.connect(
      '$_endpoint?TrustedClientToken=$_trustedClientToken'
      '&ConnectionId=$connectionId'
      '&Sec-MS-GEC=$secMsGec'
      '&Sec-MS-GEC-Version=$_secMsGecVersion',
      headers: {
        'Pragma': 'no-cache',
        'Cache-Control': 'no-cache',
        'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
        'Accept-Encoding': 'gzip, deflate, br, zstd',
        'Accept-Language': 'en-US,en;q=0.9',
        'User-Agent': _userAgent,
        'Cookie': 'muid=${_muid()};',
      },
      customClient: httpClient,
    ).timeout(_timeout);

    final sink = file.openWrite();
    var bytesWritten = 0;
    var sawTurnEnd = false;

    try {
      socket.add(_speechConfigMessage());
      socket.add(_ssmlMessage(
        requestId: connectionId,
        text: text,
        voice: _edgeVoiceFor(voice),
        speechRate: speechRate,
      ));

      await for (final message in socket.timeout(_timeout)) {
        if (message is String) {
          if (message.contains('Path:turn.end')) {
            sawTurnEnd = true;
            break;
          }
          continue;
        }

        if (message is List<int>) {
          final audio = _extractAudioPayload(Uint8List.fromList(message));
          if (audio == null || audio.isEmpty) continue;
          sink.add(audio);
          bytesWritten += audio.length;
        }
      }
    } finally {
      await sink.close();
      await socket.close();
    }

    if (!sawTurnEnd && bytesWritten == 0) {
      throw const TtsSynthesisException('Edge TTS did not return audio');
    }
    if (!file.existsSync() || file.lengthSync() <= 0) {
      throw const TtsSynthesisException('Edge TTS produced an empty file');
    }
  }

  String _speechConfigMessage() {
    final payload = jsonEncode({
      'context': {
        'synthesis': {
          'audio': {
            'metadataoptions': {
              'sentenceBoundaryEnabled': false,
              'wordBoundaryEnabled': false,
            },
            'outputFormat': _outputFormat,
          },
        },
      },
    });
    return 'X-Timestamp:${_edgeDateString()}\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '$payload\r\n';
  }

  String _ssmlMessage({
    required String requestId,
    required String text,
    required String voice,
    required double speechRate,
  }) {
    final rate = ((speechRate - 1.0) * 100).round().clamp(-50, 100);
    final ssml = '<speak version="1.0" '
        'xmlns="http://www.w3.org/2001/10/synthesis" '
        'xmlns:mstts="https://www.w3.org/2001/mstts" '
        'xml:lang="zh-CN">'
        '<voice name="$voice">'
        '<prosody rate="$rate%">${_escapeXml(text)}</prosody>'
        '</voice>'
        '</speak>';
    return 'X-RequestId:$requestId\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'X-Timestamp:${_edgeDateString()}Z\r\n'
        'Path:ssml\r\n\r\n'
        '$ssml';
  }

  Uint8List? _extractAudioPayload(Uint8List frame) {
    if (frame.length > 2) {
      final headerLength = frame[0] * 256 + frame[1];
      final payloadStart = headerLength + 2;
      if (headerLength > 0 && payloadStart <= frame.length) {
        final header = utf8.decode(
          frame.sublist(2, payloadStart),
          allowMalformed: true,
        );
        if (header.contains('Path:audio')) {
          return frame.sublist(payloadStart);
        }
      }
    }

    const separator = [13, 10, 13, 10];
    for (var i = 0; i <= frame.length - separator.length; i++) {
      if (frame[i] == separator[0] &&
          frame[i + 1] == separator[1] &&
          frame[i + 2] == separator[2] &&
          frame[i + 3] == separator[3]) {
        final header = utf8.decode(frame.sublist(0, i), allowMalformed: true);
        if (!header.contains('Path:audio')) return null;
        return frame.sublist(i + separator.length);
      }
    }
    return null;
  }

  String _edgeVoiceFor(String voice) {
    return switch (voice) {
      'zh-TW' => 'zh-TW-HsiaoChenNeural',
      'zh-HK' => 'zh-HK-HiuMaanNeural',
      _ => 'zh-CN-XiaoxiaoNeural',
    };
  }

  String _edgeDateString() {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now().toUtc();
    final two = (int value) => value.toString().padLeft(2, '0');
    return '${weekdays[now.weekday - 1]} '
        '${months[now.month - 1]} '
        '${two(now.day)} '
        '${now.year} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)} '
        'GMT+0000 (Coordinated Universal Time)';
  }

  String _generateSecMsGec() {
    var ticks = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    ticks += _windowsEpochSeconds;
    ticks -= ticks % 300;
    final fileTimeTicks = ticks * 10000000;
    final payload = '$fileTimeTicks$_trustedClientToken';
    return sha256.convert(ascii.encode(payload)).toString().toUpperCase();
  }

  String _connectionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  String _muid() => _connectionId().toUpperCase();

  String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

class TtsSynthesisException implements Exception {
  final String message;

  const TtsSynthesisException(this.message);

  @override
  String toString() => message;
}
