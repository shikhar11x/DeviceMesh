import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Deterministic CPU workload. Derives `sizeBytes` of pseudo-random data from
/// (seed, chunkIndex), then hashes it with SHA-256 (`rounds` times).
/// Same inputs always give the same digest, so results can be verified.
/// Large chunks must run in an isolate (wired up in the scheduler step).
class ChecksumExecutor {
  const ChecksumExecutor();

  static const int maxChunkBytes = 8 * 1024 * 1024;
  static const int maxRounds = 1000;

  String run({
    required int seed,
    required int chunkIndex,
    required int sizeBytes,
    int rounds = 1,
  }) {
    if (sizeBytes < 0 || sizeBytes > maxChunkBytes) {
      throw ArgumentError.value(sizeBytes, 'sizeBytes', 'out of range');
    }
    if (rounds < 1 || rounds > maxRounds) {
      throw ArgumentError.value(rounds, 'rounds', 'out of range');
    }

    // xorshift32, masked to 32 bits so it is identical on every device.
    var state = (seed ^ (chunkIndex * 0x9E3779B1)) & 0xFFFFFFFF;
    if (state == 0) state = 0x6D2B79F5;

    final data = Uint8List(sizeBytes);
    for (var i = 0; i < sizeBytes; i++) {
      state ^= (state << 13) & 0xFFFFFFFF;
      state ^= state >> 17;
      state ^= (state << 5) & 0xFFFFFFFF;
      data[i] = state & 0xFF;
    }

    var digest = sha256.convert(data);
    for (var r = 1; r < rounds; r++) {
      digest = sha256.convert(digest.bytes);
    }
    return digest.toString();
  }
}