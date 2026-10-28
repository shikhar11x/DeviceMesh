import 'package:devicemesh/features/tasks/data/result_intake.dart';
import 'package:devicemesh/features/tasks/domain/job_models.dart';
import 'package:devicemesh/features/tasks/domain/task_book.dart';
import 'package:devicemesh/features/tasks/domain/task_state.dart';
import 'package:devicemesh/features/workloads/data/checksum_runner.dart';
import 'package:devicemesh/features/workloads/domain/checksum_job_spec.dart';
import 'package:devicemesh/services/protocol/message_type.dart';
import 'package:devicemesh/services/protocol/protocol_message.dart';
import 'package:devicemesh/services/scheduler/result_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const runner = DirectChecksumRunner();
  final t0 = DateTime(2026, 1, 1);

  late TaskBook book;
  late JobCounters counters;
  late ResultIntake intake;
  var changes = 0;

  setUp(() {
    book = TaskBook(const ChecksumJobSpec(
      seed: 3,
      chunkCount: 3,
      chunkSizeBytes: 2048,
    ).plan(jobId: 'j', now: t0));
    counters = JobCounters();
    changes = 0;
    intake = ResultIntake(
      book: book,
      verifier: const ResultVerifier(runner: runner, spotCheckEvery: 1),
      counters: counters,
      onChanged: () => changes++,
      clock: () => t0,
    );
    book.assign('j-t0', workerId: 'w1', attemptId: 'a1', now: t0);
  });

  ProtocolMessage msg(
    MessageType type,
    String sender,
    Map<String, dynamic> payload,
  ) {
    return ProtocolMessage.create(
      type: type,
      senderDeviceId: sender,
      sessionId: 's',
      payload: payload,
    );
  }

  Future<Map<String, dynamic>> resultPayload({
    String taskId = 'j-t0',
    String attemptId = 'a1',
    String? digest,
  }) async {
    return {
      'taskId': taskId,
      'attemptId': attemptId,
      'digest': digest ?? await runner.run(book.byId(taskId)!.params),
      'executionMicros': 7,
    };
  }

  test('a correct result from the owner completes the task', () async {
    await intake.handle(
      'w1',
      msg(MessageType.taskResult, 'w1', await resultPayload()),
    );
    final task = book.byId('j-t0')!;
    expect(task.state, TaskState.completed);
    expect(task.validation, ResultValidation.spotChecked);
    expect(changes, greaterThan(0));
  });

  test('a result from a different worker is ignored', () async {
    await intake.handle(
      'w2',
      msg(MessageType.taskResult, 'w2', await resultPayload()),
    );
    expect(book.byId('j-t0')!.state, TaskState.assigned);
    expect(counters.stale, 1);
  });

  test('a wrong digest on a checked chunk is rejected and retried', () async {
    await intake.handle(
      'w1',
      msg(MessageType.taskResult, 'w1', await resultPayload(digest: 'a' * 64)),
    );
    final task = book.byId('j-t0')!;
    expect(counters.rejected, 1);
    expect(task.state, TaskState.queued);
    expect(task.error, contains('Rejected'));
  });

  test('a repeated result is counted as a duplicate and not applied twice',
      () async {
    final payload = await resultPayload();
    await intake.handle('w1', msg(MessageType.taskResult, 'w1', payload));
    await intake.handle('w1', msg(MessageType.taskResult, 'w1', payload));
    expect(counters.duplicates, 1);
    expect(book.byId('j-t0')!.state, TaskState.completed);
  });

  test('a late result from an old attempt is stale', () async {
    final oldPayload = await resultPayload(attemptId: 'a1');
    book.fail('j-t0', 'a1', message: 'lost', now: t0);
    book.assign('j-t0', workerId: 'w1', attemptId: 'a2', now: t0);

    await intake.handle('w1', msg(MessageType.taskResult, 'w1', oldPayload));
    expect(counters.stale, 1);
    expect(book.byId('j-t0')!.state, TaskState.assigned);
    expect(book.byId('j-t0')!.attemptId, 'a2');
  });

  test('malformed payloads are ignored without throwing', () async {
    await intake.handle(
      'w1',
      msg(MessageType.taskResult, 'w1', {'taskId': 5}),
    );
    expect(book.byId('j-t0')!.state, TaskState.assigned);
    expect(counters.stale, 0);
  });

  test('STARTED marks the task running', () async {
    await intake.handle(
      'w1',
      msg(MessageType.taskStarted, 'w1', {'taskId': 'j-t0', 'attemptId': 'a1'}),
    );
    expect(book.byId('j-t0')!.state, TaskState.running);
  });

  test('FAILED from the owner schedules a retry', () async {
    await intake.handle(
      'w1',
      msg(MessageType.taskFailed, 'w1', {
        'taskId': 'j-t0',
        'attemptId': 'a1',
        'message': 'boom',
      }),
    );
    final task = book.byId('j-t0')!;
    expect(task.state, TaskState.queued);
    expect(task.error, 'boom');
  });
}