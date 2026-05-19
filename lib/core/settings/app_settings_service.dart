import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Top-level accent color variants. Surfaces stay neutral (white/black) across
/// all variants — only the `primary` token rotates. Persisted by
/// [AppSettingsService.colorVariant].
enum ColorVariant { blue, mono, green }

class AppSettingsService extends ChangeNotifier {
  static const String _serverUrlKey = 'server_url';
  static const String _smartPathKey = 'smart_path_enabled';
  static const String _audioFormatOrderKey = 'audio_format_order';
  static const String _colorVariantKey = 'color_variant';
  static const String _lyricOverlayUnlockedKey = 'lyric_overlay_unlocked';
  static const String _narrationEnabledKey = 'narration_enabled';
  static const String _narrationVolumeKey = 'narration_volume';
  static const String _narrationVoiceKey = 'narration_voice';
  static const String _narrationConcurrencyKey = 'narration_concurrency';
  static const String _narrationBackendUrlKey = 'narration_backend_url';
  static const String _narrationBackendTokenKey = 'narration_backend_token';
  // 跨多个列表 ViewModel 共享的「仅看带字幕作品」筛选。收敛到此单点，
  // 取代各 VM 自行 SharedPreferences.getInstance() + dispose 回写陈旧值。
  static const String _subtitleFilterKey = 'subtitle_filter';

  static const String defaultServerUrl = 'https://api.asmr.one/api';
  static const ColorVariant defaultColorVariant = ColorVariant.blue;
  static const double defaultNarrationVolume = 0.18;
  static const String defaultNarrationVoice = 'zh-CN';
  static const List<String> defaultAudioFormatOrder = [
    'mp3',
    'flac',
    'wav',
    'opus',
    'm4a',
    'aac',
  ];

  /// Available server options
  static const Map<String, String> serverOptions = {
    'https://api.asmr.one/api': '主站 (asmr.one)',
    'https://api.asmr-100.com/api': '节点1 (asmr-100.com)',
    'https://api.asmr-200.com/api': '节点2 (asmr-200.com)',
    'https://api.asmr-300.com/api': '节点3 (asmr-300.com)',
  };

  final SharedPreferences _prefs;

  late String _serverUrl;
  late bool _smartPathEnabled;
  late List<String> _audioFormatOrder;
  late ColorVariant _colorVariant;
  late bool _lyricOverlayUnlocked;
  late bool _narrationEnabled;
  late double _narrationVolume;
  late String _narrationVoice;
  late int _narrationConcurrency;
  late String _narrationBackendUrl;
  late String _narrationBackendToken;
  late bool _hasSubtitleFilter;

  AppSettingsService(this._prefs) {
    _serverUrl = _prefs.getString(_serverUrlKey) ?? defaultServerUrl;
    _smartPathEnabled = _prefs.getBool(_smartPathKey) ?? true;
    final savedOrder = _prefs.getStringList(_audioFormatOrderKey);
    _audioFormatOrder = savedOrder ?? List.from(defaultAudioFormatOrder);
    final savedVariant = _prefs.getString(_colorVariantKey);
    _colorVariant = ColorVariant.values.firstWhere(
      (v) => v.name == savedVariant,
      orElse: () => defaultColorVariant,
    );
    _lyricOverlayUnlocked = _prefs.getBool(_lyricOverlayUnlockedKey) ?? false;
    _narrationEnabled = _prefs.getBool(_narrationEnabledKey) ?? false;
    _narrationVolume =
        _prefs.getDouble(_narrationVolumeKey) ?? defaultNarrationVolume;
    _narrationVoice =
        _prefs.getString(_narrationVoiceKey) ?? defaultNarrationVoice;
    _narrationConcurrency =
        (_prefs.getInt(_narrationConcurrencyKey) ?? 1).clamp(1, 2).toInt();
    _narrationBackendUrl = _prefs.getString(_narrationBackendUrlKey) ?? '';
    _narrationBackendToken = _prefs.getString(_narrationBackendTokenKey) ?? '';
    _hasSubtitleFilter = _prefs.getBool(_subtitleFilterKey) ?? false;
  }

  // === Server URL ===
  String get serverUrl => _serverUrl;

  Future<void> setServerUrl(String url) async {
    if (_serverUrl == url) return;
    _serverUrl = url;
    notifyListeners();
    await _prefs.setString(_serverUrlKey, url);
  }

  // === Smart Path ===
  bool get smartPathEnabled => _smartPathEnabled;

  Future<void> setSmartPathEnabled(bool enabled) async {
    if (_smartPathEnabled == enabled) return;
    _smartPathEnabled = enabled;
    notifyListeners();
    await _prefs.setBool(_smartPathKey, enabled);
  }

  // === Subtitle Filter (shared across list ViewModels) ===
  bool get hasSubtitleFilter => _hasSubtitleFilter;

  Future<void> setHasSubtitleFilter(bool value) async {
    if (_hasSubtitleFilter == value) return;
    _hasSubtitleFilter = value;
    notifyListeners();
    await _prefs.setBool(_subtitleFilterKey, value);
  }

  // === Audio Format Order ===
  List<String> get audioFormatOrder => List.unmodifiable(_audioFormatOrder);

  /// Get supported audio file extensions with dot prefix, ordered by preference
  List<String> get audioExtensions =>
      _audioFormatOrder.map((f) => '.$f').toList();

  Future<void> setAudioFormatOrder(List<String> order) async {
    _audioFormatOrder = List.from(order);
    notifyListeners();
    await _prefs.setStringList(_audioFormatOrderKey, _audioFormatOrder);
  }

  Future<void> resetAudioFormatOrder() async {
    await setAudioFormatOrder(List.from(defaultAudioFormatOrder));
  }

  // === Lyric Overlay Lock ===
  /// `true` → 悬浮歌词可拖动调整位置；`false` → 锁定（点穿，默认）。
  bool get lyricOverlayUnlocked => _lyricOverlayUnlocked;

  Future<void> setLyricOverlayUnlocked(bool unlocked) async {
    if (_lyricOverlayUnlocked == unlocked) return;
    _lyricOverlayUnlocked = unlocked;
    notifyListeners();
    await _prefs.setBool(_lyricOverlayUnlockedKey, unlocked);
  }

  // === Realtime narration ===
  bool get narrationEnabled => _narrationEnabled;
  double get narrationVolume => _narrationVolume;
  String get narrationVoice => _narrationVoice;
  int get narrationConcurrency => _narrationConcurrency;
  String get narrationBackendUrl => _narrationBackendUrl;
  String get narrationBackendToken => _narrationBackendToken;

  Future<void> setNarrationEnabled(bool enabled) async {
    if (_narrationEnabled == enabled) return;
    _narrationEnabled = enabled;
    notifyListeners();
    await _prefs.setBool(_narrationEnabledKey, enabled);
  }

  Future<void> setNarrationVolume(double volume) async {
    final next = volume.clamp(0.0, 0.4).toDouble();
    if (_narrationVolume == next) return;
    _narrationVolume = next;
    notifyListeners();
    await _prefs.setDouble(_narrationVolumeKey, next);
  }

  Future<void> setNarrationVoice(String voice) async {
    if (_narrationVoice == voice) return;
    _narrationVoice = voice;
    notifyListeners();
    await _prefs.setString(_narrationVoiceKey, voice);
  }

  Future<void> setNarrationConcurrency(int concurrency) async {
    final next = concurrency.clamp(1, 2).toInt();
    if (_narrationConcurrency == next) return;
    _narrationConcurrency = next;
    notifyListeners();
    await _prefs.setInt(_narrationConcurrencyKey, next);
  }

  Future<void> setNarrationBackendUrl(String url) async {
    final next = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (_narrationBackendUrl == next) return;
    _narrationBackendUrl = next;
    notifyListeners();
    await _prefs.setString(_narrationBackendUrlKey, next);
  }

  Future<void> setNarrationBackendToken(String token) async {
    final next = token.trim();
    if (_narrationBackendToken == next) return;
    _narrationBackendToken = next;
    notifyListeners();
    await _prefs.setString(_narrationBackendTokenKey, next);
  }

  // === Color Variant ===
  ColorVariant get colorVariant => _colorVariant;

  Future<void> setColorVariant(ColorVariant variant) async {
    if (_colorVariant == variant) return;
    _colorVariant = variant;
    notifyListeners();
    await _prefs.setString(_colorVariantKey, variant.name);
  }
}
