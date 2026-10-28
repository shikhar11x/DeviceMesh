import '../../workloads/domain/checksum_params.dart';
import '../../workloads/domain/task_type.dart';
import 'task_state.dart';

/// One chunk of a job. Immutable: every transition returns a new task, and an
/// illegal transition throws [StateError].
class DistributedTask {
  const DistributedTask({
    required this.id,
    required this.jobId,
    required this.index,
    required this.type,
    required this.params,
    required this.createdAt,
    this.state = TaskState.queued,
    this.attempt = 0,
    this.attemptId,
    this.workerId,
    this.retrySafe = true,
    this.notBefore,
    this.assignedAt,
    this.startedAt,
    this.completedAt,
    this.digest,
    this.executionMicros,
    this.error,
    this.validation,
  });

  static const Object _keep = Object();

  final String id;
  final String jobId;
  final int index;
  final TaskType type;
  final ChecksumParams params;
  final DateTime createdAt;
  final TaskState state;

  /// Number of times this task was handed to a worker.
  final int attempt;

  /// Identifies the current attempt. Results from other attempts are stale.
  final String? attemptId;
  final String? workerId;

  /// Only retry-safe tasks may be re-run after a failure or a lost worker.
  final bool retrySafe;

  /// Earliest time a queued task may be assigned again (retry backoff).
  final DateTime? notBefore;
  final DateTime? assignedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? digest;
  final int? executionMicros;
  final String? error;
  final ResultValidation? validation;

  DistributedTask assign({
    required String workerId,
    required String attemptId,
    required DateTime now,
  }) {
    _require(state == TaskState.queued, 'assign');
    return _copy(
      state: TaskState.assigned,
      attempt: attempt + 1,
      attemptId: attemptId,
      workerId: workerId,
      notBefore: null,
      assignedAt: now,
      startedAt: null,
      completedAt: null,
      digest: null,
      executionMicros: null,
      validation: null,
    );
  }

  DistributedTask start(DateTime now) {
    _require(state == TaskState.assigned, 'start');
    return _copy(state: TaskState.running, startedAt: now);
  }

  DistributedTask complete({
    required String digest,
    required int executionMicros,
    required ResultValidation validation,
    required DateTime now,
  }) {
    _require(state.isActive, 'complete');
    return _copy(
      state: TaskState.completed,
      digest: digest,
      executionMicros: executionMicros,
      validation: validation,
      completedAt: now,
      error: null,
    );
  }

  /// Back to the queue for another attempt. Retry-safe tasks only.
  DistributedTask requeue({required String error, required DateTime notBefore}) {
    _require(state.isActive && retrySafe, 'requeue');
    return _copy(
      state: TaskState.queued,
      attemptId: null,
      workerId: null,
      notBefore: notBefore,
      assignedAt: null,
      startedAt: null,
      error: error,
    );
  }

  DistributedTask fail({required String error, required DateTime now}) {
    _require(state.isActive, 'fail');
    return _copy(state: TaskState.failed, error: error, completedAt: now);
  }

  DistributedTask cancel(DateTime now) {
    _require(!state.isTerminal, 'cancel');
    return _copy(state: TaskState.cancelled, completedAt: now);
  }

  void _require(bool ok, String action) {
    if (!ok) {
      throw StateError('Cannot $action task $id in state ${state.name}');
    }
  }

  DistributedTask _copy({
    TaskState? state,
    int? attempt,
    Object? attemptId = _keep,
    Object? workerId = _keep,
    Object? notBefore = _keep,
    Object? assignedAt = _keep,
    Object? startedAt = _keep,
    Object? completedAt = _keep,
    Object? digest = _keep,
    Object? executionMicros = _keep,
    Object? error = _keep,
    Object? validation = _keep,
  }) {
    return DistributedTask(
      id: id,
      jobId: jobId,
      index: index,
      type: type,
      params: params,
      createdAt: createdAt,
      retrySafe: retrySafe,
      state: state ?? this.state,
      attempt: attempt ?? this.attempt,
      attemptId:
          identical(attemptId, _keep) ? this.attemptId : attemptId as String?,
      workerId:
          identical(workerId, _keep) ? this.workerId : workerId as String?,
      notBefore:
          identical(notBefore, _keep) ? this.notBefore : notBefore as DateTime?,
      assignedAt: identical(assignedAt, _keep)
          ? this.assignedAt
          : assignedAt as DateTime?,
      startedAt:
          identical(startedAt, _keep) ? this.startedAt : startedAt as DateTime?,
      completedAt: identical(completedAt, _keep)
          ? this.completedAt
          : completedAt as DateTime?,
      digest: identical(digest, _keep) ? this.digest : digest as String?,
      executionMicros: identical(executionMicros, _keep)
          ? this.executionMicros
          : executionMicros as int?,
      error: identical(error, _keep) ? this.error : error as String?,
      validation: identical(validation, _keep)
          ? this.validation
          : validation as ResultValidation?,
    );
  }
}