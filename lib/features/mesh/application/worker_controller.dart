import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/networking/mesh_client.dart';
import '../../devices/data/local_capabilities.dart';
import 'identity_provider.dart';
import 'log_provider.dart';

/// Parses "host" or "host:port". Returns null for empty or invalid input.
({String host, int port})? parseEndpoint(
  String input, {
  int defaultPort = 8080,
}) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final parts = text.split(':');
  final host = parts[0].trim();
  if (host.isEmpty || parts.length > 2) return null;
  if (parts.length == 1) return (host: host, port: defaultPort);
  final port = int.tryParse(parts[1].trim());
  if (port == null || port < 1 || port > 65535) return null;
  return (host: host, port: port);
}

/// Immutable snapshot of this phone acting as a worker.
class WorkerState {
  const WorkerState({
    this.connecting = false,
    this.connected = false,
    this.paired = false,
    this.pairing = false,
    this.heartbeatOn = false,
    this.latencyMs,
  });

  final bool connecting;
  final bool connected;
  final bool paired;
  final bool pairing;
  final bool heartbeatOn;
  final double? latencyMs;

  WorkerState copyWith({
    bool? connecting,
    bool? connected,
    bool? paired,
    bool? pairing,
    bool? heartbeatOn,
    double? latencyMs,
    bool clearLatency = false,
  }) {
    return WorkerState(
      connecting: connecting ?? this.connecting,
      connected: connected ?? this.connected,
      paired: paired ?? this.paired,
      pairing: pairing ?? this.pairing,
      heartbeatOn: heartbeatOn ?? this.heartbeatOn,
      latencyMs: clearLatency ? null : (latencyMs ?? this.latencyMs),
    );
  }
}

class WorkerController extends Notifier<WorkerState> {
  MeshClient? _client;

  /// Memory only. Secure storage comes in the security step.
  String? _savedToken;
  bool _disposed = false;

  @override
  WorkerState build() {
    ref.onDispose(() {
      _disposed = true;
      final client = _client;
      _client = null;
      client?.disconnect();
    });
    return const WorkerState();
  }

  Future<void> connect(String input) async {
    if (_client != null || state.connecting) return;
    final endpoint = parseEndpoint(input);
    if (endpoint == null) {
      _log('Enter a valid coordinator IP (optionally host:port)');
      return;
    }
    _publish(state.copyWith(connecting: true));

    final id = await ref.read(deviceIdProvider.future);
    final client = MeshClient(
      deviceId: id,
      deviceName: deviceNameFor(id),
      capabilities: LocalCapabilities.detect(),
      onLog: _log,
      onLatency: (ms) => _publish(state.copyWith(latencyMs: ms)),
      onDisconnected: _onLost,
    );

    _log('Connecting to ${endpoint.host}:${endpoint.port} ...');
    final ok = await client.connect(
      endpoint.host,
      endpoint.port,
      resumeToken: _savedToken,
    );
    if (_disposed) {
      await client.disconnect();
      return;
    }
    if (!ok) {
      _publish(state.copyWith(connecting: false));
      return;
    }
    _client = client;
    _publish(state.copyWith(
      connecting: false,
      connected: true,
      paired: client.isPaired,
    ));
    _log(client.isPaired
        ? 'Connected (session resumed)'
        : 'Connected. Enter the pairing code.');
  }

  Future<void> pair(String code) async {
    final client = _client;
    if (client == null || state.pairing || state.paired) return;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _log('Enter the 6-digit code');
      return;
    }
    _publish(state.copyWith(pairing: true));
    _log('Waiting for coordinator approval ...');
    final outcome = await client.pair(code);
    if (_disposed) return;
    if (outcome == PairOutcome.approved) {
      _savedToken = client.sessionToken;
      _publish(state.copyWith(pairing: false, paired: true));
      _log('Paired');
    } else {
      if (_client != null) _publish(state.copyWith(pairing: false));
      _log('Pairing failed: ${outcome.name}');
    }
  }

  void toggleHeartbeat() {
    final client = _client;
    if (client == null || !state.paired) return;
    if (state.heartbeatOn) {
      client.stopHeartbeat();
      _publish(state.copyWith(heartbeatOn: false, clearLatency: true));
    } else {
      client.startHeartbeat();
      _publish(state.copyWith(heartbeatOn: true));
    }
  }

  Future<void> disconnect() async {
    final client = _client;
    _client = null;
    await client?.disconnect();
    _publish(const WorkerState());
  }

  void _onLost() {
    _client = null;
    _publish(const WorkerState());
  }

  void _publish(WorkerState next) {
    if (!_disposed) state = next;
  }

  void _log(String message) {
    if (!_disposed) ref.read(logProvider.notifier).add(message);
  }
}

final workerProvider = NotifierProvider<WorkerController, WorkerState>(
  WorkerController.new,
);