import '../../features/workloads/domain/checksum_params.dart';
import '../../features/workloads/domain/task_type.dart';

String _id(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > 128) {
    throw FormatException('$key must be a non-empty string up to 128 chars');
  }
  return value;
}

int _int(Map<String, dynamic> json, String key, int min, int max) {
  final value = json[key];
  if (value is! int || value < min || value > max) {
    throw FormatException('$key must be an integer in $min..$max');
  }
  return value;
}

/// Points at one attempt of one task (ACCEPT, STARTED, CANCEL).
class TaskRef {
  const TaskRef({required this.taskId, required this.attemptId});

  factory TaskRef.fromJson(Map<String, dynamic> json) => TaskRef(
        taskId: _id(json, 'taskId'),
        attemptId: _id(json, 'attemptId'),
      );

  final String taskId;
  final String attemptId;

  Map<String, dynamic> toJson() => {'taskId': taskId, 'attemptId': attemptId};
}

/// TASK_ASSIGN. Only known workloads are accepted: no scripts, no code.
class TaskAssignPayload {
  const TaskAssignPayload({
    required this.jobId,
    required this.taskId,
    required this.attemptId,
    required this.type,
    required this.params,
    required this.timeoutMs,
  });

  static const int minTimeoutMs = 1000;
  static const int maxTimeoutMs = 600000;

  factory TaskAssignPayload.fromJson(Map<String, dynamic> json) {
    final typeRaw = json['type'];
    final type = typeRaw is String ? TaskType.fromWire(typeRaw) : null;
    if (type != TaskType.checksum) {
      throw const FormatException('Unsupported task type');
    }
    final params = json['params'];
    if (params is! Map<String, dynamic>) {
      throw const FormatException('params must be an object');
    }
    return TaskAssignPayload(
      jobId: _id(json, 'jobId'),
      taskId: _id(json, 'taskId'),
      attemptId: _id(json, 'attemptId'),
      type: type!,
      params: ChecksumParams.fromJson(params),
      timeoutMs: _int(json, 'timeoutMs', minTimeoutMs, maxTimeoutMs),
    );
  }

  final String jobId;
  final String taskId;
  final String attemptId;
  final TaskType type;
  final ChecksumParams params;
  final int timeoutMs;

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'taskId': taskId,
        'attemptId': attemptId,
        'type': type.wire,
        'params': params.toJson(),
        'timeoutMs': timeoutMs,
      };
}

/// TASK_RESULT. The digest format is checked later by the verifier.
class TaskResultPayload {
  const TaskResultPayload({
    required this.taskId,
    required this.attemptId,
    required this.digest,
    required this.executionMicros,
  });

  factory TaskResultPayload.fromJson(Map<String, dynamic> json) {
    return TaskResultPayload(
      taskId: _id(json, 'taskId'),
      attemptId: _id(json, 'attemptId'),
      digest: _id(json, 'digest'),
      executionMicros: _int(json, 'executionMicros', 0, 1000000000000),
    );
  }

  final String taskId;
  final String attemptId;
  final String digest;
  final int executionMicros;

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'attemptId': attemptId,
        'digest': digest,
        'executionMicros': executionMicros,
      };
}

/// TASK_FAILED. The message is clipped, so it cannot flood the coordinator.
class TaskFailedPayload {
  const TaskFailedPayload({
    required this.taskId,
    required this.attemptId,
    required this.message,
  });

  static const int maxMessageLength = 200;

  factory TaskFailedPayload.fromJson(Map<String, dynamic> json) {
    final message = json['message'];
    if (message is! String) {
      throw const FormatException('message must be a string');
    }
    return TaskFailedPayload(
      taskId: _id(json, 'taskId'),
      attemptId: _id(json, 'attemptId'),
      message: message.length > maxMessageLength
          ? message.substring(0, maxMessageLength)
          : message,
    );
  }

  final String taskId;
  final String attemptId;
  final String message;

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'attemptId': attemptId,
        'message': message,
      };
}