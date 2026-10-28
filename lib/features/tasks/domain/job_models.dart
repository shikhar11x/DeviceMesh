import '../../workloads/domain/checksum_job_spec.dart';
import 'distributed_task.dart';
import 'task_state.dart';

enum JobMode { singleDevice, distributed }

enum JobStatus { running, completed, failed, cancelled }

/// What the user asks for in the Task Lab.
class JobConfig {
  const JobConfig({
    required this.spec,
    this.mode = JobMode.distributed,
    this.workerIds,
    this.includeLocal = true,
    this.taskTimeout = const Duration(seconds: 30),
    this.maxAttempts = 3,
    this.spotCheckEvery = 4,
    this.localConcurrency = 1,
  });

  final ChecksumJobSpec spec;
  final JobMode mode;

  /// Restrict remote work to these devices. Null means every eligible device.
  final Set<String>? workerIds;

  /// Let the coordinator compute chunks too (distributed mode only).
  final bool includeLocal;
  final Duration taskTimeout;
  final int maxAttempts;
  final int spotCheckEvery;
  final int localConcurrency;
}

/// Mutable counters owned by one running job.
class JobCounters {
  int duplicates = 0;
  int stale = 0;
  int rejected = 0;
}

/// Immutable picture of a job at one moment. Safe to hand to the UI.
class JobSnapshot {
  const JobSnapshot({
    required this.jobId,
    required this.mode,
    required this.status,
    required this.tasks,
    required this.elapsed,
    required this.duplicates,
    required this.stale,
    required this.rejected,
    this.aggregate,
    this.message,
  });

  final String jobId;
  final JobMode mode;
  final JobStatus status;
  final List<DistributedTask> tasks;

  /// Wall-clock time since the job started (monotonic clock).
  final Duration elapsed;
  final int duplicates;
  final int stale;
  final int rejected;

  /// Final job digest, only when every chunk completed.
  final String? aggregate;
  final String? message;

  int get total => tasks.length;

  bool get isDone => status != JobStatus.running;

  int countIn(TaskState state) => tasks.where((t) => t.state == state).length;

  /// Extra attempts beyond the first, across all tasks.
  int get retries => tasks.fold<int>(
      0, (sum, t) => sum + (t.attempt > 1 ? t.attempt - 1 : 0));

  /// Completed chunks per worker ID.
  Map<String, int> get completedByWorker {
    final result = <String, int>{};
    for (final t in tasks) {
      final worker = t.workerId;
      if (t.state == TaskState.completed && worker != null) {
        result[worker] = (result[worker] ?? 0) + 1;
      }
    }
    return result;
  }
}