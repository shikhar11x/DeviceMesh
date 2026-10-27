import '../../workloads/domain/task_type.dart';

/// What a worker says it can do. Validated strictly when parsed from the
/// network, because it comes from another device.
class DeviceCapabilities {
  const DeviceCapabilities({
    required this.supportedTasks,
    required this.maxConcurrentTasks,
    required this.imageFormats,
    required this.processorCount,
  });

  static const int maxConcurrencyLimit = 8;
  static const int maxProcessorCount = 256;
  static const int maxFormats = 8;
  static const int maxListLength = 32;

  final Set<TaskType> supportedTasks;
  final int maxConcurrentTasks;
  final List<String> imageFormats;

  /// Reported by the OS (Platform.numberOfProcessors).
  final int processorCount;

  factory DeviceCapabilities.fromJson(Map<String, dynamic> json) {
    final tasksRaw = json['supportedTasks'];
    if (tasksRaw is! List || tasksRaw.length > maxListLength) {
      throw const FormatException('supportedTasks must be a short list');
    }
    final tasks = <TaskType>{};
    for (final t in tasksRaw) {
      final type = t is String ? TaskType.fromWire(t) : null;
      if (type != null) tasks.add(type); // unknown task types are ignored
    }

    final concurrency = json['maxConcurrentTasks'];
    if (concurrency is! int ||
        concurrency < 1 ||
        concurrency > maxConcurrencyLimit) {
      throw const FormatException('maxConcurrentTasks out of range');
    }

    final cpus = json['processorCount'];
    if (cpus is! int || cpus < 1 || cpus > maxProcessorCount) {
      throw const FormatException('processorCount out of range');
    }

    final formatsRaw = json['imageFormats'];
    if (formatsRaw is! List || formatsRaw.length > maxFormats) {
      throw const FormatException('imageFormats must be a short list');
    }
    final formats = <String>[];
    for (final f in formatsRaw) {
      if (f is! String || f.isEmpty || f.length > 10) {
        throw const FormatException('invalid image format');
      }
      formats.add(f);
    }

    return DeviceCapabilities(
      supportedTasks: tasks,
      maxConcurrentTasks: concurrency,
      imageFormats: formats,
      processorCount: cpus,
    );
  }

  Map<String, dynamic> toJson() => {
        'supportedTasks': [for (final t in supportedTasks) t.wire],
        'maxConcurrentTasks': maxConcurrentTasks,
        'imageFormats': imageFormats,
        'processorCount': processorCount,
      };
}