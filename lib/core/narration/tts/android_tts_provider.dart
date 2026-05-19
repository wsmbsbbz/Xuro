import 'dart:io';

import 'package:flutter/services.dart';
import 'package:xuro/core/narration/tts/tts_provider.dart';

class AndroidTtsProvider implements TtsProvider {
  static const _channel = MethodChannel('com.xuro/tts');

  @override
  String get id => 'android_tts';

  @override
  bool get isAvailable => Platform.isAndroid;

  @override
  Future<void> synthesizeToFile({
    required String text,
    required String outputPath,
    required String voice,
    double speechRate = 1.0,
  }) async {
    if (!isAvailable) {
      throw UnsupportedError('Android TTS is only available on Android');
    }
    await _channel.invokeMethod<Object?>('synthesizeToFile', {
      'text': text,
      'outputPath': outputPath,
      'locale': voice,
      'speechRate': speechRate,
    });
  }
}
