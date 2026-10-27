import '../../workloads/domain/task_type.dart';
import 'device_capabilities.dart';

enum ConnectionStatus { online, offline }

/// Coordinator's view of one worker. Immutable.
class MeshDevice {
  const MeshDevice({
    required this.id,
    required this.name,
    this.status = ConnectionStatus.online,
    this.capabilities,
    this.capabilitiesAt,
    this.lastSeen,
  });

  final String id;
  final String name;
  final ConnectionStatus status;
  final DeviceCapabilities? capabilities;

  /// When the COORDINATOR received the capabilities (its own clock).
  final DateTime? capabilitiesAt;
  final DateTime? lastSeen;

  bool get isOnline => status == ConnectionStatus.online;

  bool supports(TaskType type) =>
      capabilities?.supportedTasks.contains(type) ?? false;

  MeshDevice copyWith({
    String? name,
    ConnectionStatus? status,
    DeviceCapabilities? capabilities,
    DateTime? capabilitiesAt,
    DateTime? lastSeen,
  }) {
    return MeshDevice(
      id: id,
      name: name ?? this.name,
      status: status ?? this.status,
      capabilities: capabilities ?? this.capabilities,
      capabilitiesAt: capabilitiesAt ?? this.capabilitiesAt,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}