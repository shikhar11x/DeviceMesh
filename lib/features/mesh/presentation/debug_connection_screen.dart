import 'package:flutter/material.dart';

import '../../../core/utils/device_identity.dart';
import '../../../core/utils/local_ip.dart';
import '../../../services/networking/mesh_client.dart';
import '../../../services/networking/mesh_server.dart';

/// Development screen for the first two-phone networking milestone.
/// Uses unencrypted ws:// and no authentication. NOT the final UI.
class DebugConnectionScreen extends StatefulWidget {
  const DebugConnectionScreen({super.key});

  @override
  State<DebugConnectionScreen> createState() => _DebugConnectionScreenState();
}

class _DebugConnectionScreenState extends State<DebugConnectionScreen> {
  static const int _port = 8080;

  final _hostCtrl = TextEditingController();
  final _logs = <String>[];

  String? _deviceId;
  MeshServer? _server;
  MeshClient? _client;
  List<String> _addresses = [];
  double? _latencyMs;
  bool _connected = false;
  bool _heartbeatOn = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final id = await DeviceIdentity.getOrCreateId();
    if (!mounted) return;
    setState(() => _deviceId = id);
  }

  String get _name => 'Phone-${_deviceId?.substring(0, 4) ?? '----'}';

  void _log(String message) {
    if (!mounted) return;
    final t = TimeOfDay.now().format(context);
    setState(() {
      _logs.insert(0, '$t  $message');
      if (_logs.length > 200) _logs.removeLast();
    });
  }

  Future<void> _startServer() async {
    final id = _deviceId;
    if (id == null || _server != null) return;
    final server = MeshServer(deviceId: id, deviceName: _name, onLog: _log);
    try {
      await server.start(port: _port);
      final addrs = await LocalIp.findAll();
      if (!mounted) return;
      setState(() {
        _server = server;
        _addresses = addrs;
      });
    } catch (e) {
      _log('Server start failed: $e');
    }
  }

  Future<void> _stopServer() async {
    await _server?.stop();
    if (!mounted) return;
    setState(() {
      _server = null;
      _addresses = [];
    });
  }

  Future<void> _connect() async {
    final id = _deviceId;
    if (id == null) return;

    final input = _hostCtrl.text.trim();
    if (input.isEmpty) {
      _log('Enter the coordinator IP first');
      return;
    }
    final parts = input.split(':');
    final host = parts[0];
    final port = parts.length > 1 ? int.tryParse(parts[1]) ?? _port : _port;

    final client = MeshClient(
      deviceId: id,
      deviceName: _name,
      onLog: _log,
      onLatency: (ms) {
        if (mounted) setState(() => _latencyMs = ms);
      },
      onDisconnected: () {
        if (mounted) {
          setState(() {
            _connected = false;
            _heartbeatOn = false;
            _latencyMs = null;
          });
        }
      },
    );

    _log('Connecting to $host:$port ...');
    final ok = await client.connect(host, port);
    if (!mounted) return;
    setState(() {
      _client = ok ? client : null;
      _connected = ok;
    });
    if (ok) _log('Connected');
  }

  Future<void> _disconnect() async {
    await _client?.disconnect();
    if (!mounted) return;
    setState(() {
      _client = null;
      _connected = false;
      _heartbeatOn = false;
      _latencyMs = null;
    });
  }

  void _toggleHeartbeat() {
    final c = _client;
    if (c == null) return;
    if (_heartbeatOn) {
      c.stopHeartbeat();
    } else {
      c.startHeartbeat();
    }
    setState(() => _heartbeatOn = !_heartbeatOn);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _server?.stop();
    _client?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('DeviceMesh  Network Debug')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DEV MODE: ws:// unencrypted, no authentication',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: const Color(0xFFFFBE55)),
              ),
              const SizedBox(height: 4),
              Text('This device: $_name', style: theme.textTheme.bodyMedium),
              const Divider(height: 24),
              Text('Coordinator', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton(
                    onPressed: _server == null ? _startServer : null,
                    child: const Text('Start server'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _server != null ? _stopServer : null,
                    child: const Text('Stop'),
                  ),
                ],
              ),
              if (_server != null) ...[
                const SizedBox(height: 8),
                Text('Listening on port $_port. Use one of these IPs:',
                    style: theme.textTheme.bodySmall),
                for (final a in _addresses)
                  SelectableText(a,
                      style: const TextStyle(fontFamily: 'monospace')),
              ],
              const Divider(height: 24),
              Text('Worker', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _hostCtrl,
                enabled: !_connected,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Coordinator IP (e.g. 192.168.1.5)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _connected ? null : _connect,
                    child: const Text('Connect'),
                  ),
                  OutlinedButton(
                    onPressed: _connected ? _disconnect : null,
                    child: const Text('Disconnect'),
                  ),
                  OutlinedButton(
                    onPressed: _connected ? _toggleHeartbeat : null,
                    child: Text(_heartbeatOn
                        ? 'Stop heartbeat'
                        : 'Start heartbeat'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _connected
                    ? 'Connected'
                        '${_latencyMs != null ? '  |  RTT ${_latencyMs!.toStringAsFixed(1)} ms' : ''}'
                    : 'Not connected',
              ),
              const Divider(height: 24),
              Text('Log', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Expanded(
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (_, i) => Text(
                    _logs[i],
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}