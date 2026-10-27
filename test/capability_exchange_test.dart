// import 'dart:async';

import 'package:devicemesh/features/devices/domain/device_capabilities.dart';
import 'package:devicemesh/features/workloads/domain/task_type.dart';
import 'package:devicemesh/services/networking/mesh_client.dart';
import 'package:devicemesh/services/networking/mesh_server.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitFor(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
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

  late MeshServer server;
  late int port;

  setUp(() async {
    server = MeshServer(deviceId: 'server-1', deviceName: 'Server');
    server.onPairRequest = (r) => server.approve(r.deviceId);
    port = await server.start(port: 0);
  });

  tearDown(() async {
    await server.stop();
  });

  Future<MeshClient> paired(
    String id, {
    DeviceCapabilities? capabilities,
  }) async {
    final c = MeshClient(
      deviceId: id,
      deviceName: 'Client $id',
      capabilities: capabilities,
    );
    expect(await c.connect('127.0.0.1', port), isTrue);
    expect(await c.pair(server.pairing.issueCode()), PairOutcome.approved);
    return c;
  }

  test('paired worker advertises capabilities to the registry', () async {
    final c = await paired('w-1', capabilities: caps);
    await waitFor(() => server.registry.byId('w-1')?.capabilities != null);

    final d = server.registry.byId('w-1')!;
    expect(d.isOnline, isTrue);
    expect(d.supports(TaskType.checksum), isTrue);
    expect(d.supports(TaskType.imageResize), isFalse);
    expect(
      server.registry.eligibleFor(TaskType.checksum).map((x) => x.id),
      ['w-1'],
    );
    await c.disconnect();
  });

  test('worker that advertised nothing is not eligible', () async {
    final c = await paired('w-2');
    await waitFor(() => server.registry.byId('w-2') != null);
    expect(server.registry.eligibleFor(TaskType.checksum), isEmpty);
    await c.disconnect();
  });

  test('disconnected worker becomes offline and ineligible', () async {
    final c = await paired('w-3', capabilities: caps);
    await waitFor(() => server.registry.byId('w-3')?.capabilities != null);
    await c.disconnect();
    await waitFor(() => server.registry.byId('w-3')?.isOnline == false);
    expect(server.registry.eligibleFor(TaskType.checksum), isEmpty);
  });

  test('revoked worker is removed from the registry', () async {
    final c = await paired('w-4', capabilities: caps);
    await waitFor(() => server.registry.byId('w-4') != null);
    server.revoke('w-4');
    expect(server.registry.byId('w-4'), isNull);
    await c.disconnect();
  });

  test('resumed worker comes back online and eligible', () async {
    final c1 = await paired('w-5', capabilities: caps);
    final token = c1.sessionToken!;
    await waitFor(() => server.registry.byId('w-5')?.capabilities != null);
    await c1.disconnect();
    await waitFor(() => server.registry.byId('w-5')?.isOnline == false);

    final c2 =
        MeshClient(deviceId: 'w-5', deviceName: 'Client', capabilities: caps);
    expect(await c2.connect('127.0.0.1', port, resumeToken: token), isTrue);
    await waitFor(() => server.registry.byId('w-5')?.isOnline == true);
    expect(
      server.registry.eligibleFor(TaskType.checksum).map((x) => x.id),
      ['w-5'],
    );
    await c2.disconnect();
  });
}