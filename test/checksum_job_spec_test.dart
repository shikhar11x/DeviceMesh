import 'package:devicemesh/features/tasks/domain/task_state.dart';
import 'package:devicemesh/features/workloads/domain/checksum_job_spec.dart';
import 'package:devicemesh/features/workloads/domain/checksum_params.dart';
import 'package:devicemesh/features/workloads/domain/task_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const valid = ChecksumJobSpec(
    seed: 42,
    chunkCount: 8,
    chunkSizeBytes: 64 * 1024,
    rounds: 2,
  );

  group('ChecksumJobSpec', () {
    test('a valid spec has no problem', () {
      expect(valid.validate(), isNull);
      expect(valid.totalBytes, 8 * 64 * 1024);
    });

    test('rejects out-of-range values', () {
      const bad = [
        ChecksumJobSpec(seed: -1, chunkCount: 1, chunkSizeBytes: 2048),
        ChecksumJobSpec(seed: 1, chunkCount: 0, chunkSizeBytes: 2048),
        ChecksumJobSpec(seed: 1, chunkCount: 257, chunkSizeBytes: 2048),
        ChecksumJobSpec(seed: 1, chunkCount: 1, chunkSizeBytes: 100),
        ChecksumJobSpec(seed: 1, chunkCount: 1, chunkSizeBytes: 5000000),
        ChecksumJobSpec(
            seed: 1, chunkCount: 1, chunkSizeBytes: 2048, rounds: 0),
        ChecksumJobSpec(
            seed: 1, chunkCount: 1, chunkSizeBytes: 2048, rounds: 51),
      ];
      for (final spec in bad) {
        expect(spec.validate(), isNotNull);
      }
    });

    test('plans one queued task per chunk with unique stable IDs', () {
      final tasks = valid.plan(jobId: 'job1', now: DateTime(2026));
      expect(tasks, hasLength(8));
      expect(tasks.map((t) => t.id).toSet(), hasLength(8));
      expect(tasks.first.id, 'job1-t0');
      expect(
        tasks.every(
            (t) => t.state == TaskState.queued && t.type == TaskType.checksum),
        isTrue,
      );
      expect(tasks[3].params.chunkIndex, 3);
      expect(tasks[3].params.seed, 42);
      expect(tasks[3].params.rounds, 2);
    });

    test('plan refuses an invalid spec', () {
      const spec = ChecksumJobSpec(seed: 1, chunkCount: 0, chunkSizeBytes: 2048);
      expect(
        () => spec.plan(jobId: 'j', now: DateTime(2026)),
        throwsArgumentError,
      );
    });
  });

  group('ChecksumParams', () {
    test('round-trips through JSON', () {
      const params =
          ChecksumParams(seed: 7, chunkIndex: 2, sizeBytes: 4096, rounds: 3);
      final again = ChecksumParams.fromJson(params.toJson());
      expect(again.seed, 7);
      expect(again.chunkIndex, 2);
      expect(again.sizeBytes, 4096);
      expect(again.rounds, 3);
    });

    test('rejects invalid fields from the network', () {
      Map<String, dynamic> base() =>
          {'seed': 1, 'chunkIndex': 0, 'sizeBytes': 2048, 'rounds': 1};
      final badFields = <Map<String, dynamic>>[
        {'seed': -5},
        {'seed': 'x'},
        {'chunkIndex': 999},
        {'sizeBytes': 10},
        {'sizeBytes': 99999999},
        {'rounds': 0},
        {'rounds': 1.5},
      ];
      for (final bad in badFields) {
        final json = base()..addAll(bad);
        expect(() => ChecksumParams.fromJson(json), throwsFormatException,
            reason: '$bad');
      }
      expect(() => ChecksumParams.fromJson({}), throwsFormatException);
    });
  });
}