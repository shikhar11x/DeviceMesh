import 'package:devicemesh/features/devices/data/device_registry.dart';
import 'package:devicemesh/features/devices/domain/device_capabilities.dart';
import 'package:devicemesh/features/workloads/domain/task_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const caps = DeviceCapabilities(
    supportedTasks: {TaskType.checksum},
    maxConcurrentTasks: 1,
    imageFormats: [],
    processorCount: 4,
  );

  late DateTime now;
  late DeviceRegistry registry;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    registry = DeviceRegistry(clock: () => now);
  });

  test('connected adds an online device', () {
    registry.connected('a', 'Alpha');
    final d = registry.byId('a')!;
    expect(d.isOnline, isTrue);
    expect(d.name, 'Alpha');
    expect(d.capabilities, isNull);
  });

  test('capabilities for an unknown device are ignored', () {
    expect(registry.setCapabilities('x', caps), isFalse);
    expect(registry.byId('x'), isNull);
  });

  test('capabilities are stamped with the coordinator clock', () {
    registry.connected('a', 'Alpha');
    now = now.add(const Duration(seconds: 5));
    expect(registry.setCapabilities('a', caps), isTrue);
    expect(registry.byId('a')!.capabilitiesAt, now);
  });

  test('eligibleFor skips offline, unsupported and unadvertised devices', () {
    registry.connected('a', 'A');
    registry.setCapabilities('a', caps);
    registry.connected('b', 'B'); // never advertised
    registry.connected('c', 'C');
    registry.setCapabilities('c', caps);
    registry.disconnected('c');

    expect(registry.eligibleFor(TaskType.checksum).map((d) => d.id), ['a']);
    expect(registry.eligibleFor(TaskType.imageResize), isEmpty);
  });

  test('reconnect keeps previously advertised capabilities', () {
    registry.connected('a', 'A');
    registry.setCapabilities('a', caps);
    registry.disconnected('a');
    expect(registry.byId('a')!.isOnline, isFalse);
    registry.connected('a', 'A');
    expect(registry.byId('a')!.isOnline, isTrue);
    expect(registry.byId('a')!.capabilities, isNotNull);
  });

  test('markSeen updates lastSeen and remove deletes the device', () {
    registry.connected('a', 'A');
    now = now.add(const Duration(seconds: 10));
    registry.markSeen('a');
    expect(registry.byId('a')!.lastSeen, now);
    registry.remove('a');
    expect(registry.byId('a'), isNull);
  });
}