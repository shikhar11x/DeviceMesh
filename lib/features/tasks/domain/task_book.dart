import 'distributed_task.dart';
import 'task_state.dart';

/// Execution errors come from the task itself; transport errors mean the
/// worker was lost. They are kept apart on purpose.
enum FailureKind { execution, transport }

enum EventDisposition {
  applied,
  duplicate,
  stale,
  unknown,
  retryScheduled,
  failedFinal,
}

/// All tasks of one job and the rules for changing them. Pure Dart.
/// Results and failures are matched by task ID AND attempt ID, so late or
/// repeated messages can never overwrite a final result.
class TaskBook {
  TaskBook(
    Iterable<DistributedTask> tasks, {
    this.maxAttempts = 3,
    this.backoffBase = const Duration(milliseconds: 500),
    this.maxBackoff = const Duration(seconds: 8),
  }) : _tasks = {for (final t in tasks) t.id: t};

  final int maxAttempts;
  final Duration backoffBase;
  final Duration maxBackoff;
  final Map<String, DistributedTask> _tasks;

  /// Snapshot sorted by chunk index.
  List<DistributedTask> get tasks =>
      _tasks.values.toList()..sort((a, b) => a.index.compareTo(b.index));

  DistributedTask? byId(String id) => _tasks[id];

  int get total => _tasks.length;

  int countIn(TaskState state) =>
      _tasks.values.where((t) => t.state == state).length;

  bool get isFinished => _tasks.values.every((t) => t.state.isTerminal);

  bool get allCompleted =>
      _tasks.values.every((t) => t.state == TaskState.completed);

  /// Queued tasks whose retry backoff has expired.
  List<DistributedTask> queuedReady(DateTime now) => [
        for (final t in tasks)
          if (t.state == TaskState.queued &&
              (t.notBefore == null || !t.notBefore!.isAfter(now)))
            t,
      ];

  List<DistributedTask> activeOf(String workerId) => [
        for (final t in tasks)
          if (t.state.isActive && t.workerId == workerId) t,
      ];

  int activeCount(String workerId) => activeOf(workerId).length;

  void assign(
    String taskId, {
    required String workerId,
    required String attemptId,
    required DateTime now,
  }) {
    final task = _tasks[taskId];
    if (task == null) throw ArgumentError('Unknown task $taskId');
    _tasks[taskId] =
        task.assign(workerId: workerId, attemptId: attemptId, now: now);
  }

  /// False if the message belongs to an old attempt or the wrong state.
  bool markRunning(String taskId, String attemptId, DateTime now) {
    final task = _tasks[taskId];
    if (task == null ||
        task.state != TaskState.assigned ||
        task.attemptId != attemptId) {
      return false;
    }
    _tasks[taskId] = task.start(now);
    return true;
  }

  EventDisposition complete(
    String taskId,
    String attemptId, {
    required String digest,
    required int executionMicros,
    required ResultValidation validation,
    required DateTime now,
  }) {
    final task = _tasks[taskId];
    if (task == null) return EventDisposition.unknown;
    if (task.state == TaskState.completed) return EventDisposition.duplicate;
    if (!task.state.isActive || task.attemptId != attemptId) {
      return EventDisposition.stale;
    }
    _tasks[taskId] = task.complete(
      digest: digest,
      executionMicros: executionMicros,
      validation: validation,
      now: now,
    );
    return EventDisposition.applied;
  }

  EventDisposition fail(
    String taskId,
    String attemptId, {
    required String message,
    required DateTime now,
    FailureKind kind = FailureKind.execution,
  }) {
    final task = _tasks[taskId];
    if (task == null) return EventDisposition.unknown;
    if (task.state == TaskState.completed) return EventDisposition.duplicate;
    if (!task.state.isActive || task.attemptId != attemptId) {
      return EventDisposition.stale;
    }
    return _retryOrFail(task, message, now, kind);
  }

  /// The worker disconnected: every unfinished attempt on it is released.
  /// Retry-safe tasks go back to the queue immediately (no backoff).
  List<DistributedTask> workerLost(String workerId, DateTime now) {
    final affected = <DistributedTask>[];
    for (final task in activeOf(workerId)) {
      _retryOrFail(
        task,
        'Worker $workerId lost',
        now,
        FailureKind.transport,
      );
      affected.add(_tasks[task.id]!);
    }
    return affected;
  }

  void cancelAll(DateTime now) {
    for (final task in tasks) {
      if (!task.state.isTerminal) _tasks[task.id] = task.cancel(now);
    }
  }

  EventDisposition _retryOrFail(
    DistributedTask task,
    String message,
    DateTime now,
    FailureKind kind,
  ) {
    if (task.retrySafe && task.attempt < maxAttempts) {
      final delay =
          kind == FailureKind.transport ? Duration.zero : _backoff(task.attempt);
      _tasks[task.id] = task.requeue(error: message, notBefore: now.add(delay));
      return EventDisposition.retryScheduled;
    }
    _tasks[task.id] = task.fail(error: message, now: now);
    return EventDisposition.failedFinal;
  }

  /// Exponential: base, 2x base, 4x base ... capped at [maxBackoff].
  Duration _backoff(int attempt) {
    final ms = backoffBase.inMilliseconds * (1 << (attempt - 1));
    final capped =
        ms > maxBackoff.inMilliseconds ? maxBackoff.inMilliseconds : ms;
    return Duration(milliseconds: capped);
  }
}