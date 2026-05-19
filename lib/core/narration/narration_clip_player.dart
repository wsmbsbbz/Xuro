import 'package:just_audio/just_audio.dart';
import 'package:xuro/utils/logger.dart';

class NarrationClipPlayer {
  final AudioPlayer _player = AudioPlayer();

  Future<void> playFile(String path, {required double volume}) async {
    try {
      await _player.stop();
      await _player.setVolume(volume.clamp(0.0, 1.0));
      await _player.setFilePath(path);
      AppLogger.info('旁白播放器开始播放: path=$path volume=$volume');
      await _player.play();
    } catch (e, stack) {
      AppLogger.error('播放旁白片段失败', e, stack);
      rethrow;
    }
  }

  Future<void> playUrl(String url, {required double volume}) async {
    try {
      await _player.stop();
      await _player.setVolume(volume.clamp(0.0, 1.0));
      await _player.setUrl(url);
      AppLogger.info('旁白播放器开始播放远程片段: url=$url volume=$volume');
      await _player.play();
    } catch (e, stack) {
      AppLogger.error('播放远程旁白片段失败', e, stack);
      rethrow;
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (e) {
      AppLogger.debug('停止旁白片段失败: $e');
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
