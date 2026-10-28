import 'package:devicemesh/features/devices/domain/device_capabilities.dart';
import 'package:devicemesh/features/tasks/data/job_runner.dart';
import 'package:devicemesh/features/tasks/data/worker_task_handler.dart';
import 'package:devicemesh/features/tasks/domain/job_aggregator.dart';
import 'package:devicemesh/features/tasks/domain/job_models.dart';
import 'package:devicemesh/features/tasks/domain/task_state.dart';
import 'package:devicemesh/features/workloads/data/checksum_runner.dart';
import 'package:devicemesh/features/workloads/domain/checksum_job_spec.dart';
import 'package:devicemesh/features/workloads/domain/task_type.dart';
import 'package:devicemesh/services/networking/mesh_client.dart';
import 'package:devicemesh/services/networking/mesh_server.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitFor(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Condition not met in time');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  const caps = DeviceCapabilities(
    supportedTasks: {TaskType.checksum},
    maxConcurrentTasks: 2,
    imageFormats: [],
    processorCount: 4,
  );
  const spec = ChecksumJobSpec(
    seed: 7,
    chunkCount: 8,
    chunkSizeBytes: 8192,
    rounds: 2,
  );

  late MeshServer server;
  late int port;
  final clients = <MeshClient>[];
  JobRunner? runner;
  JobSnapshot? last;

  /// What a single device would compute for the same job.
  Future<String> baseline() async {
    final tasks = spec.plan(jobId: 'base', now: DateTime(2026));
    return JobAggregator.fromDigests([
      for (final t in tasks) await const DirectChecksumRunner().run(t.params),
    ]);
  }

  setUp(() async {
    server = MeshServer(deviceId: 'coord', deviceName: 'Coordinator');
    server.onPairRequest = (r) => server.approve(r.deviceId);
    port = await server.start(port: 0);
    clients.clear();
    runner = null;
    last = null;
  });

  tearDown(() async {
    runner?.dispose();
    for (final c in clients) {
      await c.disconnect();
    }
    await server.stop();
  });

  JobRunner makeRunner({
    Duration tick = const Duration(milliseconds: 50),
    Duration timeoutGrace = const Duration(milliseconds: 100),
    Duration noWorkerGrace = const Duration(seconds: 5),
  }) {
    final r = JobRunner(
      coordinatorId: 'coord',
      registry: server.registry,
      send: server.sendTo,
      runner: const IsolateChecksumRunner(),
      tick: tick,
      timeoutGrace: timeoutGrace,
      noWorkerGrace: noWorkerGrace,
      onUpdate: (s) => last = s,
    );
    server.onTaskMessage = r.onTaskMessage;
    server.onDeviceLost = r.onWorkerLost;
    runner = r;
    return r;
  }

  /// A paired worker. A non-responsive one accepts the connection but never
  /// answers task messages (a hung phone).
  Future<MeshClient> startWorker(String id, {bool responsive = true}) async {
    late final MeshClient client;
    final handler = WorkerTaskHandler(
      send: (type, payload) => client.sendTask(type, payload),
      runner: const IsolateChecksumRunner(),
      maxConcurrent: 2,
    );
    client = MeshClient(
      deviceId: id,
      deviceName: id,
      capabilities: caps,
      onTaskMessage: responsive ? handler.handle : null,
    );
    clients.add(client);
    expect(await client.connect('127.0.0.1', port), isTrue);
    expect(await client.pair(server.pairing.issueCode()), PairOutcome.approved);
    await waitFor(() => server.registry.byId(id)?.capabilities != null);
    return client;
  }

  test('two real workers give the same result as one device', () async {
    await startWorker('w-a');
    await startWorker('w-b');
    final r = makeRunner();

    final snap = await r
        .run(const JobConfig(spec: spec, includeLocal: false))
        .timeout(const Duration(seconds: 15));

    expect(snap.status, JobStatus.completed);
    expect(snap.aggregate, await baseline());
    expect(snap.completedByWorker.keys, unorderedEquals(['w-a', 'w-b']));
    expect(snap.completedByWorker.values.fold<int>(0, (a, b) => a + b), 8);
    expect(snap.rejected, 0);
  });

  test('single-device mode computes everything on the coordinator', () async {
    final r = makeRunner();
    final snap = await r
        .run(const JobConfig(spec: spec, mode: JobMode.singleDevice))
        .timeout(const Duration(seconds: 15));

    expect(snap.status, JobStatus.completed);
    expect(snap.completedByWorker.keys, ['coord']);
    expect(snap.aggregate, await baseline());
  });

  test('the coordinator can contribute next to its workers', () async {
    await startWorker('w-a');
    await startWorker('w-b');
    final r = makeRunner();

    final snap = await r.run(const JobConfig(spec: spec)).timeout(
          const Duration(seconds: 15),
        );

    expect(snap.status, JobStatus.completed);
    expect(snap.completedByWorker.keys, contains('coord'));
    expect(snap.aggregate, await baseline());
  });

  test('a worker that disconnects mid-job has its chunks reassigned',
      () async {
    await startWorker('w-good');
    final stall = await startWorker('w-stall', responsive: false);
    final r = makeRunner();

    final future = r.run(const JobConfig(spec: spec, includeLocal: false));
    await waitFor(() =>
        last?.tasks.any((t) => t.workerId == 'w-stall' && t.state.isActive) ??
        false);
    await stall.disconnect();

    final snap = await future.timeout(const Duration(seconds: 15));
    expect(snap.status, JobStatus.completed);
    expect(snap.retries, greaterThan(0));
    expect(snap.completedByWorker.keys, ['w-good']);
    expect(snap.aggregate, await baseline());
  });

  test('an unresponsive worker times out and the job still completes',
      () async {
    await startWorker('w-good');
    await startWorker('w-stall', responsive: false);
    final r = makeRunner();

    final snap = await r
        .run(const JobConfig(
          spec: spec,
          includeLocal: false,
          taskTimeout: Duration(seconds: 1),
        ))
        .timeout(const Duration(seconds: 20));

    expect(snap.status, JobStatus.completed);
    expect(snap.retries, greaterThan(0));
    expect(snap.completedByWorker.keys, ['w-good']);
    expect(snap.aggregate, await baseline());
  });

  test('cancel stops the job and reports cancelled', () async {
    await startWorker('w-stall', responsive: false);
    final r = makeRunner();

    final future = r.run(const JobConfig(spec: spec, includeLocal: false));
    await waitFor(() => last?.tasks.any((t) => t.workerId == 'w-stall') ?? false);

    // Only one job at a time.
    expect(() => r.run(const JobConfig(spec: spec)), throwsStateError);

    r.cancel();
    final snap = await future.timeout(const Duration(seconds: 5));
    expect(snap.status, JobStatus.cancelled);
    expect(snap.countIn(TaskState.cancelled), snap.total);
    expect(snap.aggregate, isNull);
  });

  test('a job with no workers fails after the grace period', () async {
    final r = makeRunner(noWorkerGrace: const Duration(milliseconds: 300));
    final snap = await r
        .run(const JobConfig(spec: spec, includeLocal: false))
        .timeout(const Duration(seconds: 5));

    expect(snap.status, JobStatus.failed);
    expect(snap.message, contains('No eligible workers'));
  });

  test('an invalid spec is refused before anything starts', () {
    final r = makeRunner();
    expect(
      () => r.run(const JobConfig(
        spec: ChecksumJobSpec(seed: 1, chunkCount: 0, chunkSizeBytes: 2048),
      )),
      throwsArgumentError,
    );
    expect(r.isRunning, isFalse);
  });
}