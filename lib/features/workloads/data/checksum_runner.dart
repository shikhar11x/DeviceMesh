import 'dart:isolate';

import '../domain/checksum_params.dart';
import 'checksum_executor.dart';

/// Runs one chunk and returns its SHA-256 digest.
abstract interface class ChecksumRunner {
  Future<String> run(ChecksumParams params);
}

/// Runs on the current isolate. For tests and tiny chunks only.
class DirectChecksumRunner implements ChecksumRunner {
  const DirectChecksumRunner();

  @override
  Future<String> run(ChecksumParams params) async {
    return const ChecksumExecutor().run(
      seed: params.seed,
      chunkIndex: params.chunkIndex,
      sizeBytes: params.sizeBytes,
      rounds: params.rounds,
    );
  }
}

/// Runs in a background isolate, so the UI never freezes.
class IsolateChecksumRunner implements ChecksumRunner {
  const IsolateChecksumRunner();

  @override
  Future<String> run(ChecksumParams params) {
    return Isolate.run(
      () => const ChecksumExecutor().run(
        seed: params.seed,
        chunkIndex: params.chunkIndex,
        sizeBytes: params.sizeBytes,
        rounds: params.rounds,
      ),
    );
  }
}