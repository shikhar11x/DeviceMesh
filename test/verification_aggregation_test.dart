import 'package:devicemesh/features/tasks/domain/job_aggregator.dart';
import 'package:devicemesh/features/tasks/domain/task_book.dart';
import 'package:devicemesh/features/tasks/domain/task_state.dart';
import 'package:devicemesh/features/workloads/data/checksum_runner.dart';
import 'package:devicemesh/features/workloads/domain/checksum_job_spec.dart';
import 'package:devicemesh/features/workloads/domain/checksum_params.dart';
import 'package:devicemesh/services/scheduler/result_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const runner = DirectChecksumRunner();
  final now = DateTime(2026, 1, 1);
  const spec = ChecksumJobSpec(seed: 5, chunkCount: 4, chunkSizeBytes: 2048);

  group('runners', () {
    test('the isolate runner matches the direct runner', () async {
      const params =
          ChecksumParams(seed: 7, chunkIndex: 1, sizeBytes: 4096, rounds: 2);
      final direct = await const DirectChecksumRunner().run(params);
      final isolate = await const IsolateChecksumRunner().run(params);
      expect(isolate, direct);
    });
  });

  group('ResultVerifier', () {
    final tasks = spec.plan(jobId: 'j', now: now);

    test('accepts a correct digest and spot-checks chosen chunks', () async {
      const verifier = ResultVerifier(runner: runner, spotCheckEvery: 2);
      final digest = await runner.run(tasks[0].params);
      final result = await verifier.verify(tasks[0], digest);
      expect(result.isAccepted, isTrue);
      expect(result.validation, ResultValidation.spotChecked);
    });

    test('rejects a well-formed but wrong digest on a spot-checked chunk',
        () async {
      const verifier = ResultVerifier(runner: runner, spotCheckEvery: 2);
      final result = await verifier.verify(tasks[2], 'a' * 64);
      expect(result.isAccepted, isFalse);
      expect(result.rejection, contains('recomputation'));
    });

    test('rejects malformed digests', () async {
      const verifier = ResultVerifier(runner: runner, spotCheckEvery: 0);
      for (final bad in ['xyz', '', 'A' * 64, 'a' * 63]) {
        expect((await verifier.verify(tasks[1], bad)).isAccepted, isFalse,
            reason: bad);
      }
    });

    test('other chunks are only format-checked (documented limitation)',
        () async {
      const verifier = ResultVerifier(runner: runner, spotCheckEvery: 2);
      final result = await verifier.verify(tasks[1], 'a' * 64);
      expect(result.isAccepted, isTrue);
      expect(result.validation, ResultValidation.formatOnly);
    });

    test('spotCheckEvery 0 never recomputes', () async {
      const verifier = ResultVerifier(runner: runner, spotCheckEvery: 0);
      final result = await verifier.verify(tasks[0], 'a' * 64);
      expect(result.validation, ResultValidation.formatOnly);
    });
  });

  group('JobAggregator', () {
    test('depends on every digest and on their order', () {
      final base = JobAggregator.fromDigests(['a' * 64, 'b' * 64]);
      expect(JobAggregator.fromDigests(['a' * 64, 'b' * 64]), base);
      expect(JobAggregator.fromDigests(['a' * 64, 'c' * 64]), isNot(base));
      expect(JobAggregator.fromDigests(['b' * 64, 'a' * 64]), isNot(base));
    });

    test('fromTasks ignores completion order', () async {
      final tasks = spec.plan(jobId: 'j', now: now);
      final digests = [for (final t in tasks) await runner.run(t.params)];
      final book = TaskBook(tasks);
      for (final i in [2, 0, 3, 1]) {
        book.assign('j-t$i', workerId: 'w', attemptId: 'a$i', now: now);
        book.complete(
          'j-t$i',
          'a$i',
          digest: digests[i],
          executionMicros: 1,
          validation: ResultValidation.formatOnly,
          now: now,
        );
      }
      expect(
        JobAggregator.fromTasks(book.tasks),
        JobAggregator.fromDigests(digests),
      );
    });

    test('fromTasks refuses an incomplete job', () {
      final book = TaskBook(spec.plan(jobId: 'j', now: now));
      expect(() => JobAggregator.fromTasks(book.tasks), throwsStateError);
      expect(() => JobAggregator.fromTasks(const []), throwsStateError);
    });
  });
}