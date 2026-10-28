import '../../features/tasks/domain/distributed_task.dart';
import '../../features/workloads/domain/task_type.dart';

/// One worker as the scheduler sees it. Built fresh before every planning
/// pass from live data, so offline devices are simply left out.
class WorkerSlot {
  const WorkerSlot({
    required this.id,
    required this.supportedTasks,
    required this.maxConcurrent,
    required this.active,
  });

  final String id;
  final Set<TaskType> supportedTasks;
  final int maxConcurrent;
  final int active;
}

class Assignment {
  const Assignment(this.taskId, this.workerId);

  final String taskId;
  final String workerId;
}

/// Capability-aware round robin with a per-worker concurrency limit.
/// Deterministic: workers are ordered by ID, and the rotation continues
/// across planning passes. Tasks that cannot be placed stay queued.
class TaskScheduler {
  int _cursor = 0;

  List<Assignment> plan(List<DistributedTask> queued, List<WorkerSlot> workers) {
    if (queued.isEmpty || workers.isEmpty) return const [];

    final slots = [...workers]..sort((a, b) => a.id.compareTo(b.id));
    final load = {for (final w in slots) w.id: w.active};
    final result = <Assignment>[];

    for (final task in queued) {
      for (var step = 0; step < slots.length; step++) {
        final i = (_cursor + step) % slots.length;
        final worker = slots[i];
        final current = load[worker.id]!;
        if (worker.supportedTasks.contains(task.type) &&
            current < worker.maxConcurrent) {
          result.add(Assignment(task.id, worker.id));
          load[worker.id] = current + 1;
          _cursor = (i + 1) % slots.length;
          break;
        }
      }
    }
    return result;
  }
}