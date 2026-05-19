abstract class TtsProvider {
  String get id;

  bool get isAvailable;

  Future<void> synthesizeToFile({
    required String text,
    required String outputPath,
    required String voice,
    double speechRate = 1.0,
  });
}
