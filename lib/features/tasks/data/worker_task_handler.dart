import 'dart:async';

import '../../../services/protocol/message_type.dart';
import '../../../services/protocol/protocol_message.dart';
import '../../../services/protocol/task_payloads.dart';
import '../../workloads/data/checksum_runner.dart';

typedef TaskSender = void Function(
  MessageType type,
  Map<String, dynamic> payload,
);

/// Worker side of a job. Validates TASK_ASSIGN, runs the chunk off the UI
/// isolate, and reports the outcome. It only runs known workloads and never
/// executes anything received over the network.
///
/// A running isolate cannot be killed: a cancelled or timed-out chunk still
/// finishes in the background, but its result is dropped.
class WorkerTaskHandler {
  WorkerTaskHandler({
    required this.send,
    required this.runner,
    this.maxConcurrent = 1,
    this.onLog,
  });

  final TaskSender send;
  final ChecksumRunner runner;
  final int maxConcurrent;
  final void Function(String message)? onLog;

  final Set<String> _running = {};
  final Set<String> _cancelled = {};

  int get activeCount => _running.length;

  Future<void> handle(ProtocolMessage message) async {
    switch (message.type) {
      case MessageType.taskAssign:
        await _onAssign(message.payload);
      case MessageType.taskCancel:
        _onCancel(message.payload);
      default:
        onLog?.call('Ignored ${message.type.wire}');
    }
  }

  Future<void> _onAssign(Map<String, dynamic> payload) async {
    final TaskAssignPayload assign;
    try {
      assign = TaskAssignPayload.fromJson(payload);
    } on FormatException catch (e) {
      onLog?.call('Rejected TASK_ASSIGN: ${e.message}');
      _rejectUnparsed(payload, e.message);
      return;
    }

    final ref = TaskRef(taskId: assign.taskId, attemptId: assign.attemptId);
    final key = '${assign.taskId}/${assign.attemptId}';
    if (_running.contains(key)) return; // duplicate delivery
    if (_running.length >= maxConcurrent) {
      _fail(ref, 'Worker busy');
      return;
    }

    _running.add(key);
    _send(MessageType.taskAccept, ref.toJson());
    _send(MessageType.taskStarted, ref.toJson());

    final watch = Stopwatch()..start();
    try {
      final digest = await runner
          .run(assign.params)
          .timeout(Duration(milliseconds: assign.timeoutMs));
      watch.stop();
      if (_cancelled.contains(key)) {
        onLog?.call('Task ${assign.taskId} was cancelled; result dropped');
        return;
      }
      _send(
        MessageType.taskResult,
        TaskResultPayload(
          taskId: assign.taskId,
          attemptId: assign.attemptId,
          digest: digest,
          executionMicros: watch.elapsedMicroseconds,
        ).toJson(),
      );
    } on TimeoutException {
      _fail(ref, 'Timed out after ${assign.timeoutMs} ms');
    } catch (e) {
      _fail(ref, 'Execution error (${e.runtimeType})');
    } finally {
      _running.remove(key);
      _cancelled.remove(key);
    }
  }

  void _onCancel(Map<String, dynamic> payload) {
    try {
      final ref = TaskRef.fromJson(payload);
      final key = '${ref.taskId}/${ref.attemptId}';
      if (_running.contains(key)) _cancelled.add(key);
    } on FormatException catch (e) {
      onLog?.call('Ignored malformed TASK_CANCEL: ${e.message}');
    }
  }

  /// Tell the coordinator right away instead of letting it wait for a timeout.
  void _rejectUnparsed(Map<String, dynamic> payload, String reason) {
    try {
      _fail(TaskRef.fromJson(payload), 'Rejected: $reason');
    } on FormatException catch (_) {
      onLog?.call('No usable task IDs, nothing to answer');
    }
  }

  void _fail(TaskRef ref, String message) {
    _send(
      MessageType.taskFailed,
      TaskFailedPayload(
        taskId: ref.taskId,
        attemptId: ref.attemptId,
        message: message,
      ).toJson(),
    );
  }

  void _send(MessageType type, Map<String, dynamic> payload) {
    try {
      send(type, payload);
    } catch (e) {
      onLog?.call('Send failed (${e.runtimeType})');
    }
  }
}