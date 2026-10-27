import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/local_ip.dart';
import '../../../services/networking/mesh_server.dart';
import '../../devices/domain/mesh_device.dart';
import 'identity_provider.dart';
import 'log_provider.dart';

/// Immutable snapshot of the coordinator for the UI.
class CoordinatorState {
  const CoordinatorState({
    this.running = false,
    this.port,
    this.addresses = const [],
    this.code,
    this.codeExpiresAt,
    this.pending = const [],
    this.devices = const [],
  });

  final bool running;
  final int? port;
  final List<String> addresses;
  final String? code;
  final DateTime? codeExpiresAt;
  final List<PeerInfo> pending;
  final List<MeshDevice> devices;
}

class CoordinatorController extends Notifier<CoordinatorState> {
  MeshServer? _server;
  List<String> _addresses = const [];
  Timer? _codeTimer;
  bool _starting = false;
  bool _disposed = false;

  @override
  CoordinatorState build() {
    ref.onDispose(() {
      _disposed = true;
      _codeTimer?.cancel();
      final server = _server;
      _server = null;
      server?.stop();
    });
    return const CoordinatorState();
  }

  Future<void> start({int port = 8080}) async {
    if (_server != null || _starting) return;
    _starting = true;
    try {
      final id = await ref.read(deviceIdProvider.future);
      final server = MeshServer(
        deviceId: id,
        deviceName: deviceNameFor(id),
        onLog: _log,
        onPeersChanged: _sync,
      );
      server.onPairRequest = (r) => _log('Join request: ${r.deviceName}');
      await server.start(port: port);
      if (_disposed) {
        await server.stop();
        return;
      }
      _addresses = await LocalIp.findAll();
      _server = server;
      _sync();
    } catch (e) {
      _log('Server start failed: $e');
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _codeTimer?.cancel();
    _server = null;
    await server.stop();
    _addresses = const [];
    _publish(const CoordinatorState());
  }

  void newCode() {
    final server = _server;
    if (server == null) return;
    server.pairing.issueCode();
    _scheduleExpiry();
    _sync();
  }

  void approve(String deviceId) {
    _server?.approve(deviceId);
  }

  void reject(String deviceId) {
    _server?.reject(deviceId);
  }

  void revoke(String deviceId) {
    _server?.revoke(deviceId);
  }

  void _scheduleExpiry() {
    _codeTimer?.cancel();
    final expires = _server?.pairing.codeExpiresAt;
    if (expires == null) return;
    final wait =
        expires.difference(DateTime.now()) + const Duration(milliseconds: 250);
    _codeTimer = Timer(wait, _sync);
  }

  void _sync() {
    final server = _server;
    if (server == null) return;
    _publish(CoordinatorState(
      running: true,
      port: server.port,
      addresses: _addresses,
      code: server.pairing.activeCode,
      codeExpiresAt: server.pairing.codeExpiresAt,
      pending: server.pendingRequests,
      devices: server.registry.devices,
    ));
  }

  void _publish(CoordinatorState next) {
    if (!_disposed) state = next;
  }

  void _log(String message) {
    if (!_disposed) ref.read(logProvider.notifier).add(message);
  }
}

final coordinatorProvider =
    NotifierProvider<CoordinatorController, CoordinatorState>(
  CoordinatorController.new,
);