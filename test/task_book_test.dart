import 'package:devicemesh/features/tasks/domain/distributed_task.dart';
import 'package:devicemesh/features/tasks/domain/task_book.dart';
import 'package:devicemesh/features/tasks/domain/task_state.dart';
import 'package:devicemesh/features/workloads/domain/checksum_job_spec.dart';
import 'package:devicemesh/features/workloads/domain/checksum_params.dart';
import 'package:devicemesh/features/workloads/domain/task_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);
  final digest = 'a' * 64;

  TaskBook makeBook({int maxAttempts = 3}) {
    final tasks = const ChecksumJobSpec(
      seed: 1,
      chunkCount: 3,
      chunkSizeBytes: 2048,
    ).plan(jobId: 'j', now: t0);
    return TaskBook(tasks, maxAttempts: maxAttempts);
  }

  EventDisposition finish(TaskBook book, String id, String attemptId,
      {String? digestOverride}) {
    return book.complete(
      id,
      attemptId,
      digest: digestOverride ?? digest,
      executionMicros: 10,
      validation: ResultValidation.formatOnly,
      now: t0,
    );
  }

  test('assign moves a queued task to assigned and counts the attempt', () {
    final book = makeBook();
    book.assign('j-t0', workerId: 'w1', attemptId: 'a1', now: t0);
    final t = book.byId('j-t0')!;
    expect(t.state, TaskState.assigned);
    expect(t.attempt, 1);
    expect(t.workerId, 'w1');
    expect(book.activeCount('w1'), 1);
  });

  test('a task cannot be assigned twice', () {
    final book = makeBook();
    book.assign('j-t0', workerId: 'w1', attemptId: 'a1', now: t0);
    expect(
      () => book.assign('j-t0', workerId: 'w2', attemptId: 'a2', now: t0),
      throwsStateError,
    );
  });

  test('a matching result completes the task', () {
    final book = makeBook();
    book.assign('j-t0', workerId: 'w1', attemptId: 'a1', now: t0);
    expect(book.markRunning('j-t0', 'a1', t0), isTrue);
    expect(book.byId('j-t0')!.state, TaskState.running);
    expect(finish(book, 'j-t0', 'a1'), EventDisposition.applied);
    final t = book.byId('j-t0')!;
    expect(t.state, TaskState.completed);
    expect(t.digest, digest);
  });

  test('a duplicate result is ignored and never overwrites', () {
    final book = makeBook();
    book.assign('j-t0', workerId: 'w1', attemptId: 'a1', now: t0);
    finish(book, 'j-t0', 'a1');
    final second =
        finish(book, 'j-t0', 'a1', digestOverride: 'b' * 64);
    expect(second, EventDisposition.duplicate);
    expect(book.byId('j-t0')!.digest, digest);
  });

  test('results for a wrong attempt or an unknown task are rejected', () {
    final book = makeBook();
    book.assign('j-t0', workerId: 'w1', attemptId: 'a1', now: t0);
    expect(finish(book, 'j-t0', 'other'), EventDisposition.stale);
    expect(book.byId('j-t0')!.state, TaskState.assigned);
    expect(finish(book, 'nope', 'a1'), EventDisposition.unknown);
    expect(finish(book, 'j-t1', 'a1'), EventDisposition.stale); // still queued
  });

  test('execution failures retry with exponential backoff, then give up', () {
    final book = makeBook();
    String fail(String attemptId) => book
        .fail('j-t0', attemptId, message: 'boom', now: t0)
        .name;

    book.assign('j-t0', workerId: 'w1', attemptId: 'a1', now: t0);
    expect(fail('a1'), 'retryScheduled');
    expect(book.byId('j-t0')!.state, TaskState.queued);
    expect(book.byId('j-t0')!.notBefore,
        t0.add(const Duration(milliseconds: 500)));
    expect(book.queuedReady(t0).map((t) => t.id), isNot(contains('j-t0')));
    expect(
      book.queuedReady(t0.add(const Duration(milliseconds: 600))).map((t) => t.id),
      contains('j-t0'),
    );

    book.assign('j-t0', workerId: 'w1', attemptId: 'a2', now: t0);
    expect(fail('a2'), 'retryScheduled');
    expect(book.byId('j-t0')!.notBefore,
        t0.add(const Duration(milliseconds: 1000)));

    book.assign('j-t0', workerId: 'w1', attemptId: 'a3', now: t0);
    expect(fail('a3'), 'failedFinal');
    expect(book.byId('j-t0')!.state, TaskState.failed);
    expect(book.byId('j-t0')!.error, 'boom');
  });

  test('a late result from an old attempt is stale after reassignment', () {
    final book = makeBook();
    book.assign('j-t0', workerId: 'w1', attemptId: 'a1', now: t0);
    book.fail('j-t0', 'a1', message: 'lost', now: t0);
    final later = t0.add(const Duration(seconds: 5));
    book.assign('j-t0', workerId: 'w2', attemptId: 'a2', now: later);

    expect(finish(book, 'j-t0', 'a1'), EventDisposition.stale);
    expect(finish(book, 'j-t0', 'a2'), EventDisposition.applied);
    expect(book.byId('j-t0')!.workerId, 'w2');
  });

  test('workerLost requeues active tasks at once and leaves others alone', () {
    final book = makeBook();
    book.assign('j-t0', workerId: 'w1', attemptId: 'a1', now: t0);
    book.assign('j-t1', workerId: 'w1', attemptId: 'a2', now: t0);
    book.assign('j-t2', workerId: 'w2', attemptId: 'a3', now: t0);

    final affected = book.workerLost('w1', t0);
    expect(affected.map((t) => t.id), unorderedEquals(['j-t0', 'j-t1']));
    expect(affected.every((t) => t.state == TaskState.queued), isTrue);
    expect(book.queuedReady(t0).map((t) => t.id), containsAll(['j-t0', 'j-t1']));
    expect(book.byId('j-t2')!.state, TaskState.assigned);
    expect(book.activeCount('w1'), 0);
  });

  test('a task that is not retry-safe fails permanently', () {
    final task = DistributedTask(
      id: 'x',
      jobId: 'j',
      index: 0,
      type: TaskType.checksum,
      params: const ChecksumParams(seed: 1, chunkIndex: 0, sizeBytes: 2048),
      createdAt: t0,
      retrySafe: false,
    );
    final book = TaskBook([task]);
    book.assign('x', workerId: 'w1', attemptId: 'a1', now: t0);
    expect(
      book.fail('x', 'a1', message: 'boom', now: t0),
      EventDisposition.failedFinal,
    );
    expect(book.byId('x')!.state, TaskState.failed);
  });

  test('cancelAll keeps completed work and ignores late results', () {
    final book = makeBook();
    book.assign('j-t0', workerId: 'w1', attemptId: 'a1', now: t0);
    book.assign('j-t1', workerId: 'w1', attemptId: 'a2', now: t0);
    finish(book, 'j-t0', 'a1');

    book.cancelAll(t0);
    expect(book.byId('j-t0')!.state, TaskState.completed);
    expect(book.byId('j-t1')!.state, TaskState.cancelled);
    expect(book.byId('j-t2')!.state, TaskState.cancelled);
    expect(finish(book, 'j-t1', 'a2'), EventDisposition.stale);
    expect(book.isFinished, isTrue);
    expect(book.allCompleted, isFalse);
  });
}