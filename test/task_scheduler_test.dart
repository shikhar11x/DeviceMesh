import 'package:devicemesh/features/tasks/domain/distributed_task.dart';
import 'package:devicemesh/features/workloads/domain/checksum_job_spec.dart';
import 'package:devicemesh/features/workloads/domain/task_type.dart';
import 'package:devicemesh/services/scheduler/task_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

List<DistributedTask> queued(int n) => ChecksumJobSpec(
      seed: 1,
      chunkCount: n,
      chunkSizeBytes: 2048,
    ).plan(jobId: 'j', now: DateTime(2026));

WorkerSlot slot(
  String id, {
  int max = 2,
  int active = 0,
  Set<TaskType> types = const {TaskType.checksum},
}) {
  return WorkerSlot(
    id: id,
    supportedTasks: types,
    maxConcurrent: max,
    active: active,
  );
}

List<String> workersOf(List<Assignment> plan) =>
    [for (final a in plan) a.workerId];

void main() {
  test('spreads tasks round robin across workers', () {
    final plan = TaskScheduler().plan(queued(4), [slot('a'), slot('b')]);
    expect(workersOf(plan), ['a', 'b', 'a', 'b']);
    expect(plan.map((a) => a.taskId), ['j-t0', 'j-t1', 'j-t2', 'j-t3']);
  });

  test('worker order in the input does not matter', () {
    final plan = TaskScheduler().plan(queued(2), [slot('b'), slot('a')]);
    expect(workersOf(plan), ['a', 'b']);
  });

  test('rotation continues between planning passes', () {
    final scheduler = TaskScheduler();
    final workers = [slot('a'), slot('b')];
    expect(workersOf(scheduler.plan(queued(1), workers)), ['a']);
    expect(workersOf(scheduler.plan(queued(1), workers)), ['b']);
  });

  test('respects concurrency limits and leaves the rest queued', () {
    final plan = TaskScheduler().plan(
      queued(3),
      [slot('a', max: 1), slot('b', max: 1)],
    );
    expect(plan, hasLength(2));
  });

  test('accounts for tasks a worker is already running', () {
    final plan = TaskScheduler().plan(
      queued(1),
      [slot('a', max: 1, active: 1), slot('b', max: 1)],
    );
    expect(workersOf(plan), ['b']);
  });

  test('skips workers without the capability', () {
    final plan = TaskScheduler().plan(
      queued(3),
      [
        slot('a', types: const {TaskType.imageResize}),
        slot('b'),
      ],
    );
    expect(workersOf(plan), ['b', 'b']); // b has max 2, third stays queued
  });

  test('no workers or no tasks gives no assignments', () {
    expect(TaskScheduler().plan(queued(2), const []), isEmpty);
    expect(TaskScheduler().plan(const [], [slot('a')]), isEmpty);
  });
}