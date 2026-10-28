import 'package:devicemesh/features/workloads/domain/task_type.dart';
import 'package:devicemesh/services/protocol/task_payloads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> validAssign() => {
        'jobId': 'job-1',
        'taskId': 'task-1',
        'attemptId': 'att-1',
        'type': 'checksum',
        'params': {'seed': 1, 'chunkIndex': 0, 'sizeBytes': 2048, 'rounds': 1},
        'timeoutMs': 5000,
      };

  group('TaskAssignPayload', () {
    test('round-trips through JSON', () {
      final assign = TaskAssignPayload.fromJson(validAssign());
      expect(assign.type, TaskType.checksum);
      expect(assign.params.sizeBytes, 2048);
      final again = TaskAssignPayload.fromJson(assign.toJson());
      expect(again.taskId, 'task-1');
      expect(again.timeoutMs, 5000);
    });

    test('rejects unsafe or unsupported input', () {
      final changes = <Map<String, dynamic>>[
        {'type': 'run_shell'},
        {'type': 'image_resize'},
        {'type': 5},
        {'timeoutMs': 10},
        {'timeoutMs': 99999999},
        {'taskId': ''},
        {'attemptId': 'x' * 200},
        {'params': 'nope'},
        {
          'params': {
            'seed': 1,
            'chunkIndex': 0,
            'sizeBytes': 999999999,
            'rounds': 1,
          },
        },
      ];
      for (final change in changes) {
        final json = validAssign()..addAll(change);
        expect(() => TaskAssignPayload.fromJson(json), throwsFormatException,
            reason: '$change');
      }
    });
  });

  group('other payloads', () {
    test('TaskRef needs both IDs', () {
      final ref = TaskRef.fromJson({'taskId': 't', 'attemptId': 'a'});
      expect(ref.toJson(), {'taskId': 't', 'attemptId': 'a'});
      expect(() => TaskRef.fromJson({'taskId': 't'}), throwsFormatException);
    });

    test('TaskResultPayload validates fields', () {
      final ok = TaskResultPayload.fromJson({
        'taskId': 't',
        'attemptId': 'a',
        'digest': 'abc',
        'executionMicros': 12,
      });
      expect(ok.executionMicros, 12);
      for (final bad in [
        {'taskId': 't', 'attemptId': 'a', 'digest': '', 'executionMicros': 1},
        {'taskId': 't', 'attemptId': 'a', 'digest': 'abc', 'executionMicros': -1},
        {'taskId': 't', 'attemptId': 'a', 'digest': 'abc'},
      ]) {
        expect(() => TaskResultPayload.fromJson(bad), throwsFormatException);
      }
    });

    test('TaskFailedPayload clips long messages', () {
      final failed = TaskFailedPayload.fromJson(
        {'taskId': 't', 'attemptId': 'a', 'message': 'x' * 500},
      );
      expect(failed.message.length, TaskFailedPayload.maxMessageLength);
      expect(
        () => TaskFailedPayload.fromJson(
            {'taskId': 't', 'attemptId': 'a', 'message': 5}),
        throwsFormatException,
      );
    });
  });
}