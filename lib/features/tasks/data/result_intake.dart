import '../../../services/protocol/message_type.dart';
import '../../../services/protocol/protocol_message.dart';
import '../../../services/protocol/task_payloads.dart';
import '../../../services/scheduler/result_verifier.dart';
import '../domain/job_models.dart';
import '../domain/task_book.dart';
import '../domain/task_state.dart';

/// Coordinator side: turns worker messages into task book changes.
///
/// A worker may only report on tasks currently assigned to it. Results are
/// verified before they are stored. Duplicates and stale attempts are counted
/// and dropped, never applied.
class ResultIntake {
  ResultIntake({
    required this.book,
    required this.verifier,
    required this.counters,
    required this.onChanged,
    this.onLog,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final TaskBook book;
  final ResultVerifier verifier;
  final JobCounters counters;
  final void Function() onChanged;
  final void Function(String message)? onLog;
  final DateTime Function() _now;

  Future<void> handle(String deviceId, ProtocolMessage message) async {
    try {
      switch (message.type) {
        case MessageType.taskAccept:
          TaskRef.fromJson(message.payload); // validated; nothing else to do
        case MessageType.taskStarted:
          final started = TaskRef.fromJson(message.payload);
          if (_owns(deviceId, started.taskId)) {
            book.markRunning(started.taskId, started.attemptId, _now());
            onChanged();
          }
        case MessageType.taskResult:
          final result = TaskResultPayload.fromJson(message.payload);
          if (_owns(deviceId, result.taskId)) {
            await applyResult(result, trusted: false);
          }
        case MessageType.taskFailed:
          final failed = TaskFailedPayload.fromJson(message.payload);
          if (_owns(deviceId, failed.taskId)) {
            _count(book.fail(
              failed.taskId,
              failed.attemptId,
              message: failed.message,
              now: _now(),
            ));
            onChanged();
          }
        default:
          onLog?.call('Ignored ${message.type.wire}');
      }
    } on FormatException catch (e) {
      onLog?.call('Ignored malformed ${message.type.wire}: ${e.message}');
    }
  }

  /// Verifies (unless [trusted]) and stores a result.
  Future<void> applyResult(
    TaskResultPayload result, {
    required bool trusted,
  }) async {
    final task = book.byId(result.taskId);
    if (task == null) {
      counters.stale++;
      return;
    }
    if (task.state == TaskState.completed) {
      counters.duplicates++;
      onChanged();
      return;
    }
    if (!task.state.isActive || task.attemptId != result.attemptId) {
      counters.stale++;
      onChanged();
      return;
    }

    final ResultValidation validation;
    if (trusted) {
      validation = ResultValidation.trustedLocal;
    } else {
      final check = await verifier.verify(task, result.digest);
      if (!check.isAccepted) {
        counters.rejected++;
        onLog?.call('Rejected result for chunk ${task.index}: ${check.rejection}');
        book.fail(
          result.taskId,
          result.attemptId,
          message: 'Rejected: ${check.rejection}',
          now: _now(),
        );
        onChanged();
        return;
      }
      validation = check.validation!;
    }

    // The state may have changed while verifying; complete() re-checks.
    _count(book.complete(
      result.taskId,
      result.attemptId,
      digest: result.digest,
      executionMicros: result.executionMicros,
      validation: validation,
      now: _now(),
    ));
    onChanged();
  }

  bool _owns(String deviceId, String taskId) {
    final task = book.byId(taskId);
    if (task == null || task.workerId != deviceId) {
      counters.stale++;
      onLog?.call('Ignored a message about a task not assigned to this device');
      onChanged();
      return false;
    }
    return true;
  }

  void _count(EventDisposition disposition) {
    switch (disposition) {
      case EventDisposition.duplicate:
        counters.duplicates++;
      case EventDisposition.stale:
        counters.stale++;
      default:
        break;
    }
  }
}