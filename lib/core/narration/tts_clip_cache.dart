import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xuro/core/narration/models/narration_segment.dart';
import 'package:xuro/utils/logger.dart';

class TtsClipCache {
  static const int _maxBytes = 200 * 1024 * 1024;

  Directory? _cacheDir;

  Future<Directory> get _dir async {
    final existing = _cacheDir;
    if (existing != null) return existing;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/narration_tts');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  Future<String> pathFor({
    required String provider,
    required String voice,
    required String text,
    double speechRate = 1.0,
    String extension = 'wav',
  }) async {
    final normalized = NarrationSegment.normalizeText(text);
    final safeExtension = extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final digest = sha256
        .convert(
          '$provider\u0000$voice\u0000$speechRate\u0000$normalized'.codeUnits,
        )
        .toString();
    return '${(await _dir).path}/$digest.$safeExtension';
  }

  Future<bool> exists(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    if (await file.length() <= 0) return false;
    await file.setLastModified(DateTime.now());
    return true;
  }

  Future<void> cleanupIfNeeded() async {
    try {
      final dir = await _dir;
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File) files.add(entity);
      }
      var total = 0;
      final entries = <({File file, int size, DateTime modified})>[];
      for (final file in files) {
        final stat = await file.stat();
        total += stat.size;
        entries.add((file: file, size: stat.size, modified: stat.modified));
      }
      if (total <= _maxBytes) return;
      entries.sort((a, b) => a.modified.compareTo(b.modified));
      for (final entry in entries) {
        if (total <= _maxBytes * 0.8) break;
        await entry.file.delete();
        total -= entry.size;
      }
    } catch (e, stack) {
      AppLogger.error('清理旁白 TTS 缓存失败', e, stack);
    }
  }
}
