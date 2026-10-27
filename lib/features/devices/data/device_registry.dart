import '../../workloads/domain/task_type.dart';
import '../domain/device_capabilities.dart';
import '../domain/mesh_device.dart';

/// Pure Dart device registry (no sockets, no widgets). Unit-testable.
class DeviceRegistry {
  DeviceRegistry({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, MeshDevice> _devices = {};

  List<MeshDevice> get devices => List.unmodifiable(_devices.values);

  MeshDevice? byId(String id) => _devices[id];

  /// Device authenticated (new or returning). Keeps old capabilities.
  void connected(String id, String name) {
    final prev = _devices[id] ?? MeshDevice(id: id, name: name);
    _devices[id] = prev.copyWith(
      name: name,
      status: ConnectionStatus.online,
      lastSeen: _now(),
    );
  }

  void disconnected(String id) {
    final d = _devices[id];
    if (d != null) {
      _devices[id] = d.copyWith(status: ConnectionStatus.offline);
    }
  }

  void markSeen(String id) {
    final d = _devices[id];
    if (d != null) _devices[id] = d.copyWith(lastSeen: _now());
  }

  /// Returns false if the device is unknown (capabilities are ignored).
  bool setCapabilities(String id, DeviceCapabilities caps) {
    final d = _devices[id];
    if (d == null) return false;
    _devices[id] = d.copyWith(capabilities: caps, capabilitiesAt: _now());
    return true;
  }

  void remove(String id) => _devices.remove(id);

  /// Online devices that advertised support for [type].
  List<MeshDevice> eligibleFor(TaskType type) => [
        for (final d in _devices.values)
          if (d.isOnline && d.supports(type)) d,
      ];
}