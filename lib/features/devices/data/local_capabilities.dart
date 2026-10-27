import 'dart:io';

import '../../workloads/domain/task_type.dart';
import '../domain/device_capabilities.dart';

/// Capabilities THIS phone can really provide right now.
/// Add a task here only after its executor exists and is tested.
class LocalCapabilities {
  const LocalCapabilities._();

  static DeviceCapabilities detect({int maxConcurrentTasks = 1}) {
    return DeviceCapabilities(
      supportedTasks: const {TaskType.checksum},
      maxConcurrentTasks: maxConcurrentTasks,
      imageFormats: const [],
      processorCount: Platform.numberOfProcessors,
    );
  }
}