import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../core/utils/format.dart';
import '../../../services/protocol/message_type.dart';
import '../../../services/protocol/protocol_message.dart';
import '../../../services/protocol/task_payloads.dart';
import '../../../services/scheduler/result_verifier.dart';
import '../../../services/scheduler/task_scheduler.dart';
import '../../devices/data/device_registry.dart';
import '../../workloads/data/checksum_runner.dart';
import '../../workloads/domain/task_type.dart';
import '../domain/distributed_task.dart';
import '../domain/job_aggregator.dart';
import '../domain/job_models.dart';
import '../domain/task_book.dart';
import '../domain/task_state.dart';
import 'result_intake.dart';

/// Sends a message to a connected device. False if it is not reachable.
typedef SendToDevice = bool Function(
  String deviceId,
  MessageType type,
  Map<String, dynamic> payload,
);

/// Runs one job at a time on the coordinator: plans chunks, assigns them to
/// workers (and optionally to itself), tracks results, handles timeouts and
/// lost workers, and aggregates the final digest.
class JobRunner {
  JobRunner({
    required this.coordinatorId,
    required this.registry,
    required this.send,
    required this.runner,
    this.tick = const Duration(milliseconds: 250),
    this.timeoutGrace = const Duration(seconds: 2),
    this.noWorkerGrace = const Duration(seconds: 15),
    this.onLog,
    this.onUpdate,
  });

  final String coordinatorId;
  final DeviceRegistry registry;
  final SendToDevice send;

  /// Used for the coordinator's own chunks and for spot-check recomputation.
  final ChecksumRunner runner;
  final Duration tick;
  final Duration timeoutGrace;
  final Duration noWorkerGrace;
  final void Function(String message)? onLog;
  final void Function(JobSnapshot snapshot)? onUpdate;

  static const Uuid _uuid = Uuid();

  final TaskScheduler _scheduler = TaskScheduler();
  final Set<String> _excluded = {};
  final Stopwatch _clock = Stopwatch();

  JobCounters _counters = JobCounters();
  TaskBook? _book;
  JobConfig? _config;
  ResultIntake? _intake;
  Completer<JobSnapshot>? _done;
  Timer? _timer;
  String _jobId = '';
  bool _finished = true;
  bool _userCancelled = false;
  String? _message;
  DateTime? _noWorkerSince;

  bool get isRunning => !_finished;

  /// Starts a job and completes when it is completed, failed or cancelled.
  Future<JobSnapshot> run(JobConfig config) {
    if (!_finished) throw StateError('A job is already running');
    final problem = config.spec.validate();
    if (problem != null) throw ArgumentError(problem);

    _jobId = _uuid.v4();
    final book = TaskBook(
      config.spec.plan(jobId: _jobId, now: DateTime.now()),
      maxAttempts: config.maxAttempts,
    );
    _book = book;
    _config = config;
    _counters = JobCounters();
    _excluded.clear();
    _finished = false;
    _userCancelled = false;
    _message = null;
    _noWorkerSince = null;
    _clock
      ..reset()
      ..start();
    _intake = ResultIntake(
      book: book,
      verifier: ResultVerifier(
        runner: runner,
        spotCheckEvery: config.spotCheckEvery,
      ),
      counters: _counters,
      onChanged: _pump,
      onLog: onLog,
    );

    final done = Completer<JobSnapshot>();
    _done = done;
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => _tick());
    onLog?.call('Job ${shortId(_jobId)} started: ${config.spec.chunkCount} chunks');
    _pump();
    return done.future;
  }

  void onTaskMessage(String deviceId, ProtocolMessage message) {
    final intake = _intake;
    if (intake == null || _finished) return;
    unawaited(intake.handle(deviceId, message));
  }

  void onWorkerLost(String deviceId) {
    final book = _book;
    if (book == null || _finished) return;
    final affected = book.workerLost(deviceId, DateTime.now());
    if (affected.isNotEmpty) {
      onLog?.call('Worker lost: ${affected.length} chunk(s) released for reassignment');
    }
    _pump();
  }

  void cancel() {
    final book = _book;
    if (book == null || _finished) return;
    _userCancelled = true;
    _cancelTasks(book, DateTime.now());
    _pump();
  }

  void dispose() {
    cancel();
    _timer?.cancel();
  }

  // ---------------------------------------------------------------- loop

  void _pump() {
    if (_finished) return;
    _step();
    _publish();
  }

  void _tick() {
    if (_finished) return;
    if (_step()) _publish();
  }

  /// One scheduling pass. Returns true if any task changed.
  bool _step() {
    final book = _book;
    final config = _config;
    if (book == null || config == null) return false;
    final now = DateTime.now();
    var changed = _expireTimedOut(book, config, now);

    final failed = book.tasks.where((t) => t.state == TaskState.failed);
    if (failed.isNotEmpty && !book.isFinished) {
      final task = failed.first;
      _message = 'Chunk ${task.index} failed: ${task.error ?? 'unknown error'}';
      _cancelTasks(book, now);
      return true;
    }

    final slots = _slots(book, config);
    for (final a in _scheduler.plan(book.queuedReady(now), slots)) {
      _dispatch(book, config, a, now);
      changed = true;
    }

    final nothingActive = book.tasks.every((t) => !t.state.isActive);
    if (slots.isEmpty && nothingActive && book.countIn(TaskState.queued) > 0) {
      final since = _noWorkerSince ??= now;
      if (now.difference(since) > noWorkerGrace) {
        _message = 'No eligible workers available';
        _cancelTasks(book, now);
        changed = true;
      }
    } else {
      _noWorkerSince = null;
    }
    return changed;
  }

  List<WorkerSlot> _slots(TaskBook book, JobConfig config) {
    final slots = <WorkerSlot>[];
    final localOnly = config.mode == JobMode.singleDevice;
    if (localOnly || config.includeLocal) {
      slots.add(WorkerSlot(
        id: coordinatorId,
        supportedTasks: const {TaskType.checksum},
        maxConcurrent: config.localConcurrency,
        active: book.activeCount(coordinatorId),
      ));
    }
    if (!localOnly) {
      final allowed = config.workerIds;
      for (final d in registry.eligibleFor(TaskType.checksum)) {
        if (_excluded.contains(d.id)) continue;
        if (allowed != null && !allowed.contains(d.id)) continue;
        final caps = d.capabilities!; // eligibleFor guarantees it
        slots.add(WorkerSlot(
          id: d.id,
          supportedTasks: caps.supportedTasks,
          maxConcurrent: caps.maxConcurrentTasks,
          active: book.activeCount(d.id),
        ));
      }
    }
    return slots;
  }

  void _dispatch(TaskBook book, JobConfig config, Assignment a, DateTime now) {
    final attemptId = _uuid.v4();
    book.assign(a.taskId, workerId: a.workerId, attemptId: attemptId, now: now);
    final task = book.byId(a.taskId)!;

    if (a.workerId == coordinatorId) {
      unawaited(_runLocal(task, attemptId));
      return;
    }

    final payload = TaskAssignPayload(
      jobId: task.jobId,
      taskId: task.id,
      attemptId: attemptId,
      type: task.type,
      params: task.params,
      timeoutMs: config.taskTimeout.inMilliseconds,
    ).toJson();
    if (!send(a.workerId, MessageType.taskAssign, payload)) {
      onLog?.call('Could not reach ${shortId(a.workerId)}');
      book.fail(
        task.id,
        attemptId,
        message: 'Send failed',
        now: now,
        kind: FailureKind.transport,
      );
    }
  }

  Future<void> _runLocal(DistributedTask task, String attemptId) async {
    final book = _book;
    final intake = _intake;
    if (book == null || intake == null) return;
    book.markRunning(task.id, attemptId, DateTime.now());
    final watch = Stopwatch()..start();
    try {
      final digest = await runner.run(task.params);
      watch.stop();
      await intake.applyResult(
        TaskResultPayload(
          taskId: task.id,
          attemptId: attemptId,
          digest: digest,
          executionMicros: watch.elapsedMicroseconds,
        ),
        trusted: true,
      );
    } catch (e) {
      book.fail(
        task.id,
        attemptId,
        message: 'Local execution error',
        now: DateTime.now(),
      );
      _pump();
    }
  }

  /// A worker that does not answer in time is released and excluded for the
  /// rest of this job, so round robin does not keep handing it new chunks.
  bool _expireTimedOut(TaskBook book, JobConfig config, DateTime now) {
    final limit = config.taskTimeout + timeoutGrace;
    var changed = false;
    for (final t in book.tasks) {
      final assignedAt = t.assignedAt;
      final worker = t.workerId;
      final attemptId = t.attemptId;
      if (!t.state.isActive ||
          assignedAt == null ||
          worker == null ||
          attemptId == null ||
          worker == coordinatorId) {
        continue;
      }
      if (now.difference(assignedAt) <= limit) continue;

      onLog?.call('Chunk ${t.index} timed out on ${shortId(worker)}; excluded for this job');
      _excluded.add(worker);
      book.fail(
        t.id,
        attemptId,
        message: 'Timed out waiting for worker',
        now: now,
        kind: FailureKind.transport,
      );
      send(worker, MessageType.taskCancel,
          TaskRef(taskId: t.id, attemptId: attemptId).toJson());
      changed = true;
    }
    return changed;
  }

  void _cancelTasks(TaskBook book, DateTime now) {
    for (final t in book.tasks) {
      final worker = t.workerId;
      final attemptId = t.attemptId;
      if (t.state.isActive &&
          worker != null &&
          attemptId != null &&
          worker != coordinatorId) {
        send(worker, MessageType.taskCancel,
            TaskRef(taskId: t.id, attemptId: attemptId).toJson());
      }
    }
    book.cancelAll(now);
  }

  // ------------------------------------------------------------- results

  void _publish() {
    final book = _book;
    if (book == null || _finished) return;
    if (book.isFinished) {
      _complete(book);
      return;
    }
    onUpdate?.call(_snapshot(JobStatus.running));
  }

  void _complete(TaskBook book) {
    _finished = true;
    _timer?.cancel();
    _clock.stop();

    final JobStatus status;
    String? aggregate;
    var message = _message;
    if (book.allCompleted) {
      status = JobStatus.completed;
      aggregate = JobAggregator.fromTasks(book.tasks);
    } else if (_userCancelled) {
      status = JobStatus.cancelled;
    } else {
      status = JobStatus.failed;
      message ??= '${book.countIn(TaskState.failed)} chunk(s) failed';
    }

    final snapshot = _snapshot(status, aggregate: aggregate, message: message);
    onLog?.call('Job ${shortId(_jobId)} ${status.name}');
    onUpdate?.call(snapshot);
    _done?.complete(snapshot);
  }

  JobSnapshot _snapshot(
    JobStatus status, {
    String? aggregate,
    String? message,
  }) {
    return JobSnapshot(
      jobId: _jobId,
      mode: _config!.mode,
      status: status,
      tasks: _book!.tasks,
      elapsed: _clock.elapsed,
      duplicates: _counters.duplicates,
      stale: _counters.stale,
      rejected: _counters.rejected,
      aggregate: aggregate,
      message: message ?? _message,
    );
  }
}