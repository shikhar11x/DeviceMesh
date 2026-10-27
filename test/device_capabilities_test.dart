import 'package:devicemesh/features/devices/domain/device_capabilities.dart';
import 'package:devicemesh/features/workloads/domain/task_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> valid() => {
        'supportedTasks': ['checksum'],
        'maxConcurrentTasks': 2,
        'imageFormats': ['jpeg'],
        'processorCount': 8,
      };

  test('round-trips through JSON', () {
    final c = DeviceCapabilities.fromJson(valid());
    expect(c.supportedTasks, {TaskType.checksum});
    final again = DeviceCapabilities.fromJson(c.toJson());
    expect(again.maxConcurrentTasks, 2);
    expect(again.processorCount, 8);
  });

  test('unknown task types are ignored, not trusted', () {
    final json = valid()..['supportedTasks'] = ['checksum', 'run_shell'];
    expect(
      DeviceCapabilities.fromJson(json).supportedTasks,
      {TaskType.checksum},
    );
  });

  test('rejects invalid values', () {
    final badFields = <Map<String, dynamic>>[
      {'maxConcurrentTasks': 0},
      {'maxConcurrentTasks': 99},
      {'processorCount': -1},
      {'supportedTasks': 'checksum'},
      {'imageFormats': List<String>.filled(20, 'png')},
    ];
    for (final bad in badFields) {
      final json = valid()..addAll(bad);
      expect(() => DeviceCapabilities.fromJson(json), throwsFormatException,
          reason: '$bad');
    }
  });
}