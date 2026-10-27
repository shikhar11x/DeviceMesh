import 'package:flutter/material.dart';
import '../../devices/data/local_capabilities.dart';
import '../../../core/utils/device_identity.dart';
import '../../../core/utils/local_ip.dart';
import '../../../services/networking/mesh_client.dart';
import '../../../services/networking/mesh_server.dart';

/// Development screen for the two-phone networking + pairing milestone.
/// Uses unencrypted ws:// and unsigned messages. NOT the final UI.
class DebugConnectionScreen extends StatefulWidget {
  const DebugConnectionScreen({super.key});

  @override
  State<DebugConnectionScreen> createState() => _DebugConnectionScreenState();
}

class _DebugConnectionScreenState extends State<DebugConnectionScreen> {
  static const int _port = 8080;
  static const _amber = Color(0xFFFFBE55);

  final _hostCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _logs = <String>[];

  String? _deviceId;
  MeshServer? _server;
  MeshClient? _client;
  List<String> _addresses = [];
  double? _latencyMs;
  bool _connected = false;
  bool _paired = false;
  bool _heartbeatOn = false;
  String? _savedToken; // in memory only (secure storage comes later)

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

  void _refresh() {
    if (mounted) setState(() {});
  }

  // ---------------- Coordinator ----------------

  Future<void> _startServer() async {
    final id = _deviceId;
    if (id == null || _server != null) return;
    final server = MeshServer(
      deviceId: id,
      deviceName: _name,
      onLog: _log,
      onPeersChanged: _refresh,
    );
    server.onPairRequest = (r) => _log('Join request: ${r.deviceName}');
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

  void _newCode() {
    _server?.pairing.issueCode();
    setState(() {});
  }

  // ---------------- Worker ----------------

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
      capabilities: LocalCapabilities.detect(),
      onLog: _log,
      onLatency: (ms) {
        if (mounted) setState(() => _latencyMs = ms);
      },
      onDisconnected: () {
        if (mounted) {
          setState(() {
            _connected = false;
            _paired = false;
            _heartbeatOn = false;
            _latencyMs = null;
          });
        }
      },
    );

    _log('Connecting to $host:$port ...');
    final ok = await client.connect(host, port, resumeToken: _savedToken);
    if (!mounted) return;
    setState(() {
      _client = ok ? client : null;
      _connected = ok;
      _paired = ok && client.isPaired;
    });
    if (ok) {
      _log(client.isPaired
          ? 'Connected (session resumed)'
          : 'Connected. Enter the pairing code.');
    }
  }

  Future<void> _pair() async {
    final c = _client;
    if (c == null) return;
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      _log('Enter the 6-digit code');
      return;
    }
    _log('Waiting for coordinator approval ...');
    final outcome = await c.pair(code);
    if (!mounted) return;
    if (outcome == PairOutcome.approved) {
      setState(() {
        _paired = true;
        _savedToken = c.sessionToken;
      });
      _log('Paired');
    } else {
      _log('Pairing failed: ${outcome.name}');
    }
  }

  Future<void> _disconnect() async {
    await _client?.disconnect();
    if (!mounted) return;
    setState(() {
      _client = null;
      _connected = false;
      _paired = false;
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
    _codeCtrl.dispose();
    _server?.stop();
    _client?.disconnect();
    super.dispose();
  }

  // ---------------- UI ----------------

  String _hms(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final server = _server;
    final code = server?.pairing.activeCode;
    final expires = server?.pairing.codeExpiresAt;

    return Scaffold(
      appBar: AppBar(title: const Text('DeviceMesh  Network Debug')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'DEV MODE: ws:// unencrypted, messages not yet signed',
              style: theme.textTheme.labelMedium?.copyWith(color: _amber),
            ),
            const SizedBox(height: 4),
            Text('This device: $_name', style: theme.textTheme.bodyMedium),
            const Divider(height: 24),

            // ---- Coordinator ----
            Text('Coordinator', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: server == null ? _startServer : null,
                  child: const Text('Start server'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: server != null ? _stopServer : null,
                  child: const Text('Stop'),
                ),
              ],
            ),
            if (server != null) ...[
              const SizedBox(height: 8),
              Text('Port $_port. IPs:', style: theme.textTheme.bodySmall),
              for (final a in _addresses)
                SelectableText(a,
                    style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.tonal(
                    onPressed: _newCode,
                    child: const Text('New pairing code'),
                  ),
                  const SizedBox(width: 12),
                  if (code != null)
                    Expanded(
                      child: Text(
                        '$code  (until ${_hms(expires!)})',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 20,
                            letterSpacing: 2),
                      ),
                    )
                  else
                    const Text('No active code'),
                ],
              ),
              const SizedBox(height: 12),
              Text('Join requests', style: theme.textTheme.titleSmall),
              if (server.pendingRequests.isEmpty)
                const Text('None', style: TextStyle(fontSize: 12)),
              for (final r in server.pendingRequests)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.deviceName),
                  subtitle: Text(r.deviceId.substring(0, 8),
                      style: const TextStyle(fontFamily: 'monospace')),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () => server.approve(r.deviceId),
                        child: const Text('Approve'),
                      ),
                      OutlinedButton(
                        onPressed: () => server.reject(r.deviceId),
                        child: const Text('Reject'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text('Paired devices', style: theme.textTheme.titleSmall),
              if (server.pairedPeers.isEmpty)
                const Text('None', style: TextStyle(fontSize: 12)),
              for (final p in server.pairedPeers)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.deviceName),
                  subtitle: Text(p.deviceId.substring(0, 8),
                      style: const TextStyle(fontFamily: 'monospace')),
                  trailing: OutlinedButton(
                    onPressed: () => server.revoke(p.deviceId),
                    child: const Text('Revoke'),
                  ),
                ),
            ],
            const Divider(height: 24),

            // ---- Worker ----
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
            TextField(
              controller: _codeCtrl,
              enabled: _connected && !_paired,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: '6-digit pairing code',
                border: OutlineInputBorder(),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _connected ? null : _connect,
                  child: const Text('Connect'),
                ),
                FilledButton.tonal(
                  onPressed: (_connected && !_paired) ? _pair : null,
                  child: const Text('Pair'),
                ),
                OutlinedButton(
                  onPressed: _connected ? _disconnect : null,
                  child: const Text('Disconnect'),
                ),
                OutlinedButton(
                  onPressed: _paired ? _toggleHeartbeat : null,
                  child: Text(
                      _heartbeatOn ? 'Stop heartbeat' : 'Start heartbeat'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              !_connected
                  ? 'Not connected'
                  : !_paired
                      ? 'Connected, NOT paired'
                      : 'Paired'
                          '${_latencyMs != null ? '  |  RTT ${_latencyMs!.toStringAsFixed(1)} ms' : ''}',
            ),
            const Divider(height: 24),

            // ---- Log ----
            Text('Log', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final l in _logs.take(60))
              Text(l,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
      ),
    );
  }
}