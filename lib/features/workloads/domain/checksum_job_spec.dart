import '../../tasks/domain/distributed_task.dart';
import 'checksum_params.dart';
import 'task_type.dart';

/// What the user asks for in the Task Lab. Validated before anything runs.
class ChecksumJobSpec {
  const ChecksumJobSpec({
    required this.seed,
    required this.chunkCount,
    required this.chunkSizeBytes,
    this.rounds = 1,
  });

  static const int maxChunks = ChecksumParams.maxChunkIndex + 1;

  final int seed;
  final int chunkCount;
  final int chunkSizeBytes;
  final int rounds;

  int get totalBytes => chunkCount * chunkSizeBytes;

  /// A readable problem, or null when the spec is valid.
  String? validate() {
    if (seed < 0 || seed > ChecksumParams.maxSeed) {
      return 'Seed must be 0..${ChecksumParams.maxSeed}';
    }
    if (chunkCount < 1 || chunkCount > maxChunks) {
      return 'Chunk count must be 1..$maxChunks';
    }
    if (chunkSizeBytes < ChecksumParams.minSizeBytes ||
        chunkSizeBytes > ChecksumParams.maxSizeBytes) {
      return 'Chunk size must be '
          '${ChecksumParams.minSizeBytes}..${ChecksumParams.maxSizeBytes} bytes';
    }
    if (rounds < 1 || rounds > ChecksumParams.maxRounds) {
      return 'Rounds must be 1..${ChecksumParams.maxRounds}';
    }
    return null;
  }

  /// One queued task per chunk. Task IDs are unique because [jobId] is.
  List<DistributedTask> plan({required String jobId, required DateTime now}) {
    final problem = validate();
    if (problem != null) throw ArgumentError(problem);
    return [
      for (var i = 0; i < chunkCount; i++)
        DistributedTask(
          id: '$jobId-t$i',
          jobId: jobId,
          index: i,
          type: TaskType.checksum,
          params: ChecksumParams(
            seed: seed,
            chunkIndex: i,
            sizeBytes: chunkSizeBytes,
            rounds: rounds,
          ),
          createdAt: now,
        ),
    ];
  }
}