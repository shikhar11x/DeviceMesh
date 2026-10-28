import 'package:devicemesh/features/tasks/domain/job_aggregator.dart';
import 'package:devicemesh/features/tasks/domain/task_book.dart';
// import 'package:devicemesh/features/tasks/domain/task_state.dart';
import 'package:devicemesh/features/workloads/data/checksum_runner.dart';
import 'package:devicemesh/features/workloads/domain/checksum_job_spec.dart';
import 'package:devicemesh/features/workloads/domain/task_type.dart';
import 'package:devicemesh/services/scheduler/result_verifier.dart';
import 'package:devicemesh/services/scheduler/task_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure logic only: no sockets, no phones. Proves that scheduling, retries,
/// duplicate protection, verification and aggregation work together.
void main() {
  test('distributed logic matches the single-device result', () async {
    const runner = DirectChecksumRunner();
    const verifier = ResultVerifier(runner: runner, spotCheckEvery: 2);
    const spec = ChecksumJobSpec(
      seed: 9,
      chunkCount: 6,
      chunkSizeBytes: 4096,
      rounds: 2,
    );
    var clock = DateTime(2026, 1, 1, 12);

    // Baseline: one device computes every chunk in order.
    final baseline = JobAggregator.fromDigests([
      for (final t in spec.plan(jobId: 'base', now: clock))
        await runner.run(t.params),
    ]);

    final book = TaskBook(spec.plan(jobId: 'j', now: clock));
    final scheduler = TaskScheduler();
    const workerIds = ['a', 'b'];
    var attemptCounter = 0;
    var guard = 0;

    while (!book.isFinished) {
      expect(guard++, lessThan(10), reason: 'job should finish quickly');

      final slots = [
        for (final id in workerIds)
          WorkerSlot(
            id: id,
            supportedTasks: const {TaskType.checksum},
            maxConcurrent: 2,
            active: book.activeCount(id),
          ),
      ];
      for (final a in scheduler.plan(book.queuedReady(clock), slots)) {
        book.assign(
          a.taskId,
          workerId: a.workerId,
          attemptId: 'att${attemptCounter++}',
          now: clock,
        );
      }

      // Results come back in reverse order. Chunk 3 fails on its first try.
      final active =
          book.tasks.where((t) => t.state.isActive).toList().reversed;
      for (final t in active) {
        if (t.index == 3 && t.attempt == 1) {
          expect(
            book.fail(t.id, t.attemptId!, message: 'boom', now: clock),
            EventDisposition.retryScheduled,
          );
          continue;
        }
        final digest = await runner.run(t.params);
        final check = await verifier.verify(t, digest);
        expect(check.isAccepted, isTrue);

        EventDisposition deliver() => book.complete(
              t.id,
              t.attemptId!,
              digest: digest,
              executionMicros: 5,
              validation: check.validation!,
              now: clock,
            );
        expect(deliver(), EventDisposition.applied);
        expect(deliver(), EventDisposition.duplicate); // repeated delivery
      }

      clock = clock.add(const Duration(seconds: 1)); // backoff expires
    }

    expect(book.allCompleted, isTrue);
    expect(book.byId('j-t3')!.attempt, 2);
    expect(JobAggregator.fromTasks(book.tasks), baseline);
  });
}