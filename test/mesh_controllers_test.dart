import 'package:devicemesh/features/mesh/application/coordinator_controller.dart';
import 'package:devicemesh/features/mesh/application/identity_provider.dart';
import 'package:devicemesh/features/mesh/application/worker_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitFor(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Condition not met in time');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

ProviderContainer makeContainer(String deviceId) {
  final container = ProviderContainer(
    overrides: [deviceIdProvider.overrideWith((ref) => deviceId)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('parseEndpoint', () {
    test('uses the default port when none is given', () {
      final e = parseEndpoint('192.168.1.5')!;
      expect(e.host, '192.168.1.5');
      expect(e.port, 8080);
    });

    test('reads an explicit port', () {
      final e = parseEndpoint(' 10.0.0.2:9000 ')!;
      expect(e.host, '10.0.0.2');
      expect(e.port, 9000);
    });

    test('rejects empty or invalid input', () {
      expect(parseEndpoint(''), isNull);
      expect(parseEndpoint(':8080'), isNull);
      expect(parseEndpoint('host:abc'), isNull);
      expect(parseEndpoint('host:70000'), isNull);
      expect(parseEndpoint('a:1:2'), isNull);
    });
  });

  test('coordinator and worker pair end to end', () async {
    final coord = makeContainer('coordinator-id-0001');
    final work = makeContainer('worker-id-0001');

    final coordCtrl = coord.read(coordinatorProvider.notifier);
    await coordCtrl.start(port: 0);
    expect(coord.read(coordinatorProvider).running, isTrue);
    final port = coord.read(coordinatorProvider).port!;

    coordCtrl.newCode();
    final code = coord.read(coordinatorProvider).code!;
    expect(code, matches(RegExp(r'^\d{6}$')));

    final workerCtrl = work.read(workerProvider.notifier);
    await workerCtrl.connect('127.0.0.1:$port');
    expect(work.read(workerProvider).connected, isTrue);
    expect(work.read(workerProvider).paired, isFalse);

    final pairing = workerCtrl.pair(code);
    await waitFor(() => coord.read(coordinatorProvider).pending.isNotEmpty);
    expect(coord.read(coordinatorProvider).code, isNull); // single use
    coordCtrl.approve(coord.read(coordinatorProvider).pending.first.deviceId);
    await pairing;
    expect(work.read(workerProvider).paired, isTrue);

    await waitFor(
      () => coord
          .read(coordinatorProvider)
          .devices
          .any((d) => d.capabilities != null),
    );
    final device = coord.read(coordinatorProvider).devices.single;
    expect(device.id, 'worker-id-0001');
    expect(device.isOnline, isTrue);

    await workerCtrl.disconnect();
    expect(work.read(workerProvider).connected, isFalse);
    await waitFor(
      () => coord.read(coordinatorProvider).devices.single.isOnline == false,
    );

    await coordCtrl.stop();
    expect(coord.read(coordinatorProvider).running, isFalse);
  });

  test('wrong code is rejected and the worker is dropped', () async {
    final coord = makeContainer('coordinator-id-0002');
    final work = makeContainer('worker-id-0002');

    final coordCtrl = coord.read(coordinatorProvider.notifier);
    await coordCtrl.start(port: 0);
    final port = coord.read(coordinatorProvider).port!;
    coordCtrl.newCode();
    final code = coord.read(coordinatorProvider).code!;
    final wrong = code == '000000' ? '111111' : '000000';

    final workerCtrl = work.read(workerProvider.notifier);
    await workerCtrl.connect('127.0.0.1:$port');
    await workerCtrl.pair(wrong);

    await waitFor(() => !work.read(workerProvider).connected);
    expect(work.read(workerProvider).paired, isFalse);
    expect(coord.read(coordinatorProvider).devices, isEmpty);

    await coordCtrl.stop();
  });
}