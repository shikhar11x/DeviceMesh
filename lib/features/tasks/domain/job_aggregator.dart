import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'distributed_task.dart';
import 'task_state.dart';

/// Combines chunk digests into one job digest. The same job gives the same
/// result whether it ran on one device or many, in any arrival order.
class JobAggregator {
  const JobAggregator._();

  /// SHA-256 over "index:digest" lines.
  static String fromDigests(List<String> digestsInIndexOrder) {
    final lines = [
      for (var i = 0; i < digestsInIndexOrder.length; i++)
        '$i:${digestsInIndexOrder[i]}',
    ];
    return sha256.convert(utf8.encode(lines.join('\n'))).toString();
  }

  /// Throws [StateError] unless every chunk completed with a digest.
  static String fromTasks(List<DistributedTask> tasks) {
    if (tasks.isEmpty) throw StateError('Job has no tasks');
    final sorted = [...tasks]..sort((a, b) => a.index.compareTo(b.index));
    final digests = <String>[];
    for (var i = 0; i < sorted.length; i++) {
      final task = sorted[i];
      final digest = task.digest;
      if (task.index != i ||
          task.state != TaskState.completed ||
          digest == null) {
        throw StateError('Job is incomplete at chunk $i');
      }
      digests.add(digest);
    }
    return fromDigests(digests);
  }
}