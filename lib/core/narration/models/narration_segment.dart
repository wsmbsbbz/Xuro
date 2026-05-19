import 'package:xuro/core/audio/models/subtitle.dart';

enum NarrationSegmentStatus { pending, generating, ready, failed }

class NarrationSegment {
  final String id;
  final Duration start;
  final Duration end;
  final String text;
  final int index;
  NarrationSegmentStatus status;
  String? audioPath;
  String? audioUrl;
  String? error;

  NarrationSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.text,
    required this.index,
    this.status = NarrationSegmentStatus.pending,
    this.audioPath,
    this.audioUrl,
    this.error,
  });

  bool contains(Duration position) => position >= start && position <= end;

  bool startsInWindow(Duration position, Duration window) {
    return start >= position && start <= position + window;
  }

  static String normalizeText(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'^[\-–—・•\s]+', multiLine: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<NarrationSegment> fromSubtitleList(SubtitleList list) {
    return list.subtitles
        .map((subtitle) {
          final normalized = normalizeText(subtitle.text);
          if (normalized.isEmpty) return null;
          return NarrationSegment(
            id: '${subtitle.index}-${subtitle.start.inMilliseconds}-${subtitle.end.inMilliseconds}',
            start: subtitle.start,
            end: subtitle.end,
            text: normalized,
            index: subtitle.index,
          );
        })
        .whereType<NarrationSegment>()
        .toList(growable: false);
  }
}
