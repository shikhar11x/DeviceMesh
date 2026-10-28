import 'dart:async';

import 'package:devicemesh/features/tasks/data/worker_task_handler.dart';
import 'package:devicemesh/features/workloads/data/checksum_runner.dart';
import 'package:devicemesh/features/workloads/domain/checksum_params.dart';
import 'package:devicemesh/services/protocol/message_type.dart';
import 'package:devicemesh/services/protocol/protocol_message.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runner that waits until the test lets it finish.
class _Gate implements ChecksumRunner {
  final Completer<String> completer = Completer<String>();

  @override
  Future<String> run(ChecksumParams params) => completer.future;
}

class _Throwing implements ChecksumRunner {
  @override
  Future<String> run(ChecksumParams params) async =>
      throw StateError('secret internal detail');
}

ProtocolMessage assign({
  String taskId = 't1',
  String attemptId = 'a1',
  Object type = 'checksum',
  Object? params,
  int timeoutMs = 5000,
}) {
  return ProtocolMessage.create(
    type: MessageType.taskAssign,
    senderDeviceId: 'coord',
    sessionId: 's',
    payload: {
      'jobId': 'j',
      'taskId': taskId,
      'attemptId': attemptId,
      'type': type,
      'params': params ??
          {'seed': 1, 'chunkIndex': 0, 'sizeBytes': 2048, 'rounds': 1},
      'timeoutMs': timeoutMs,
    },
  );
}

ProtocolMessage cancel(String taskId, String attemptId) {
  return ProtocolMessage.create(
    type: MessageType.taskCancel,
    senderDeviceId: 'coord',
    sessionId: 's',
    payload: {'taskId': taskId, 'attemptId': attemptId},
  );
}

void main() {
  final sent = <({MessageType type, Map<String, dynamic> payload})>[];

  WorkerTaskHandler make(ChecksumRunner runner, {int maxConcurrent = 1}) {
    return WorkerTaskHandler(
      send: (type, payload) => sent.add((type: type, payload: payload)),
      runner: runner,
      maxConcurrent: maxConcurrent,
    );
  }

  List<MessageType> types() => [for (final s in sent) s.type];

  setUp(sent.clear);

  test('a valid assignment is accepted, started and answered', () async {
    await make(const DirectChecksumRunner()).handle(assign());

    expect(types(), [
      MessageType.taskAccept,
      MessageType.taskStarted,
      MessageType.taskResult,
    ]);
    final result = sent.last.payload;
    expect(result['taskId'], 't1');
    expect(result['attemptId'], 'a1');
    final expected = await const DirectChecksumRunner().run(
      const ChecksumParams(seed: 1, chunkIndex: 0, sizeBytes: 2048),
    );
    expect(result['digest'], expected);
    expect(result['executionMicros'], greaterThanOrEqualTo(0));
  });

  test('bad parameters are rejected with TASK_FAILED, nothing runs', () async {
    final handler = make(const DirectChecksumRunner());
    await handler.handle(assign(params: {'seed': 1}));
    expect(types(), [MessageType.taskFailed]);
    expect(sent.single.payload['message'], contains('Rejected'));
  });

  test('an unsupported task type is rejected', () async {
    await make(const DirectChecksumRunner())
        .handle(assign(type: 'image_resize'));
    expect(types(), [MessageType.taskFailed]);
  });

  test('a message without usable IDs gets no reply', () async {
    final message = ProtocolMessage.create(
      type: MessageType.taskAssign,
      senderDeviceId: 'coord',
      sessionId: 's',
      payload: {'taskId': 5},
    );
    await make(const DirectChecksumRunner()).handle(message);
    expect(sent, isEmpty);
  });

  test('a second task is refused while the worker is busy', () async {
    final gate = _Gate();
    final handler = make(gate);
    final first = handler.handle(assign(taskId: 't1'));

    await handler.handle(assign(taskId: 't2'));
    final failed =
        sent.where((s) => s.type == MessageType.taskFailed).single;
    expect(failed.payload['taskId'], 't2');
    expect(failed.payload['message'], contains('busy'));

    gate.completer.complete('a' * 64);
    await first;
    expect(
      sent.any((s) =>
          s.type == MessageType.taskResult && s.payload['taskId'] == 't1'),
      isTrue,
    );
  });

  test('a repeated delivery of the same attempt is ignored', () async {
    final gate = _Gate();
    final handler = make(gate, maxConcurrent: 2);
    final first = handler.handle(assign());
    await handler.handle(assign());

    expect(types(), [MessageType.taskAccept, MessageType.taskStarted]);
    gate.completer.complete('a' * 64);
    await first;
  });

  test('a cancelled task never reports a result', () async {
    final gate = _Gate();
    final handler = make(gate);
    final first = handler.handle(assign());

    await handler.handle(cancel('t1', 'a1'));
    gate.completer.complete('a' * 64);
    await first;

    expect(types().contains(MessageType.taskResult), isFalse);
    expect(handler.activeCount, 0);
  });

  test('execution errors are reported without internal details', () async {
    await make(_Throwing()).handle(assign());
    expect(types().last, MessageType.taskFailed);
    final message = sent.last.payload['message'] as String;
    expect(message, contains('Execution error'));
    expect(message, isNot(contains('secret')));
  });

  test('a task that exceeds its timeout fails', () async {
    final handler = make(_Gate());
    await handler.handle(assign(timeoutMs: 1000));
    expect(types().last, MessageType.taskFailed);
    expect(sent.last.payload['message'], contains('Timed out'));
    expect(handler.activeCount, 0);
  });
}