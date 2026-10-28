/// Inputs for one checksum chunk. These travel over the network, so every
/// field is range-checked when parsed.
class ChecksumParams {
  const ChecksumParams({
    required this.seed,
    required this.chunkIndex,
    required this.sizeBytes,
    this.rounds = 1,
  });

  static const int maxSeed = 0xFFFFFFFF;
  static const int maxChunkIndex = 255;
  static const int minSizeBytes = 1024;
  static const int maxSizeBytes = 4 * 1024 * 1024;
  static const int maxRounds = 50;

  final int seed;
  final int chunkIndex;
  final int sizeBytes;
  final int rounds;

  factory ChecksumParams.fromJson(Map<String, dynamic> json) {
    return ChecksumParams(
      seed: _intInRange(json, 'seed', 0, maxSeed),
      chunkIndex: _intInRange(json, 'chunkIndex', 0, maxChunkIndex),
      sizeBytes: _intInRange(json, 'sizeBytes', minSizeBytes, maxSizeBytes),
      rounds: _intInRange(json, 'rounds', 1, maxRounds),
    );
  }

  Map<String, dynamic> toJson() => {
        'seed': seed,
        'chunkIndex': chunkIndex,
        'sizeBytes': sizeBytes,
        'rounds': rounds,
      };

  static int _intInRange(
    Map<String, dynamic> json,
    String key,
    int min,
    int max,
  ) {
    final value = json[key];
    if (value is! int || value < min || value > max) {
      throw FormatException('$key must be an integer in $min..$max');
    }
    return value;
  }
}