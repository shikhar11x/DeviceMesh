import 'package:devicemesh/features/workloads/data/checksum_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const exec = ChecksumExecutor();

  test('same input gives the same SHA-256 digest', () {
    final a = exec.run(seed: 7, chunkIndex: 3, sizeBytes: 4096);
    final b = exec.run(seed: 7, chunkIndex: 3, sizeBytes: 4096);
    expect(a, b);
    expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('changing any input changes the digest', () {
    final base = exec.run(seed: 7, chunkIndex: 3, sizeBytes: 4096);
    expect(exec.run(seed: 7, chunkIndex: 4, sizeBytes: 4096), isNot(base));
    expect(exec.run(seed: 8, chunkIndex: 3, sizeBytes: 4096), isNot(base));
    expect(exec.run(seed: 7, chunkIndex: 3, sizeBytes: 4097), isNot(base));
    expect(
      exec.run(seed: 7, chunkIndex: 3, sizeBytes: 4096, rounds: 2),
      isNot(base),
    );
  });

  test('rejects unsafe sizes and rounds', () {
    expect(() => exec.run(seed: 1, chunkIndex: 0, sizeBytes: -1),
        throwsArgumentError);
    expect(
      () => exec.run(
          seed: 1,
          chunkIndex: 0,
          sizeBytes: ChecksumExecutor.maxChunkBytes + 1),
      throwsArgumentError,
    );
    expect(() => exec.run(seed: 1, chunkIndex: 0, sizeBytes: 10, rounds: 0),
        throwsArgumentError);
  });
}