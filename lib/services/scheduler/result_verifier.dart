import '../../features/tasks/domain/distributed_task.dart';
import '../../features/tasks/domain/task_state.dart';
import '../../features/workloads/data/checksum_runner.dart';

class Verification {
  const Verification.accepted(ResultValidation this.validation)
      : rejection = null;
  const Verification.rejected(String this.rejection) : validation = null;

  final ResultValidation? validation;
  final String? rejection;

  bool get isAccepted => rejection == null;
}

/// Checks a worker's digest before it is stored.
///
/// Every digest must be well formed. Chunks whose index is a multiple of
/// [spotCheckEvery] are also recomputed locally and must match exactly.
/// Other chunks are only format-checked, so a dishonest worker could slip a
/// wrong digest through. Redundant execution would close that gap later.
class ResultVerifier {
  const ResultVerifier({required this.runner, this.spotCheckEvery = 4});

  final ChecksumRunner runner;

  /// 0 disables recomputation.
  final int spotCheckEvery;

  static final RegExp _format = RegExp(r'^[0-9a-f]{64}$');

  Future<Verification> verify(DistributedTask task, String digest) async {
    if (!_format.hasMatch(digest)) {
      return const Verification.rejected(
          'Digest is not 64 lowercase hex characters');
    }
    if (spotCheckEvery > 0 && task.index % spotCheckEvery == 0) {
      final expected = await runner.run(task.params);
      if (expected != digest) {
        return const Verification.rejected(
            'Digest does not match local recomputation');
      }
      return const Verification.accepted(ResultValidation.spotChecked);
    }
    return const Verification.accepted(ResultValidation.formatOnly);
  }
}