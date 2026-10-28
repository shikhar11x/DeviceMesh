import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../protocol/message_type.dart';
import '../protocol/protocol_codec.dart';
import '../protocol/protocol_exception.dart';
import '../protocol/protocol_message.dart';
import 'pairing_manager.dart';
import '../../features/devices/data/device_registry.dart';
import '../../features/devices/domain/device_capabilities.dart';

enum PeerState { connected, helloDone, pendingApproval, authenticated }

class PeerInfo {
  const PeerInfo({
    required this.deviceId,
    required this.deviceName,
    required this.state,
  });

  final String deviceId;
  final String deviceName;
  final PeerState state;
}

class _Peer {
  String? deviceId;
  String deviceName = 'unknown';
  PeerState state = PeerState.connected;
  Timer? approvalTimer;
}

/// DEV-MODE server: plain ws://. Pairing code + manual approval gate every
/// device, but messages are not yet signed (HMAC arrives in Day 5).
class MeshServer {
  MeshServer({
    required this.deviceId,
    required this.deviceName,
    PairingManager? pairing,
    this.codec = const ProtocolCodec(),
    this.approvalTimeout = const Duration(seconds: 60),
    this.onLog,
    this.onPeersChanged,
    this.onPairRequest,
  }) : pairing = pairing ?? PairingManager();

  final String deviceId;
  final String deviceName;
  final PairingManager pairing;
  final ProtocolCodec codec;
  final Duration approvalTimeout;
  final void Function(String message)? onLog;
  final void Function()? onPeersChanged;

  /// Called when a device presented a valid code and awaits approval.
  /// If null, join requests are rejected (nobody can approve them).
  void Function(PeerInfo request)? onPairRequest;

  /// Task messages (ACCEPT, STARTED, RESULT, FAILED) from authenticated workers.
  void Function(String deviceId, ProtocolMessage message)? onTaskMessage;

  /// An authenticated device disconnected (socket closed, revoked, replaced).
  void Function(String deviceId)? onDeviceLost;

  final DeviceRegistry registry = DeviceRegistry();

  HttpServer? _server;
  final Map<WebSocketChannel, _Peer> _peers = {};

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  List<PeerInfo> get peers => [
    for (final p in _peers.values)
      if (p.deviceId != null)
        PeerInfo(
          deviceId: p.deviceId!,
          deviceName: p.deviceName,
          state: p.state,
        ),
  ];

  List<PeerInfo> get pendingRequests =>
      peers.where((p) => p.state == PeerState.pendingApproval).toList();

  List<PeerInfo> get pairedPeers =>
      peers.where((p) => p.state == PeerState.authenticated).toList();

  /// Pass port 0 to let the OS choose a free port (used in tests).
  Future<int> start({int port = 8080}) async {
    if (_server != null) return _server!.port;
    final handler = webSocketHandler(_onConnection);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    onLog?.call('Server listening on port ${_server!.port}');
    return _server!.port;
  }

  Future<void> stop() async {
    final entries = _peers.entries.toList();
    _peers.clear();
    for (final e in entries) {
      e.value.approvalTimer?.cancel();
      try {
        _send(e.key, MessageType.goodbye, {});
        e.key.sink.close();
      } catch (_) {}
    }
    await _server?.close(force: true);
    _server = null;
    onLog?.call('Server stopped');
    _notify();
  }

  /// Approves a pending join request and issues the session token.
  bool approve(String deviceId) {
    final entry = _find(deviceId, PeerState.pendingApproval);
    if (entry == null) return false;
    final peer = entry.value;
    peer.approvalTimer?.cancel();
    final token = pairing.issueToken(deviceId);
    peer.state = PeerState.authenticated;
    registry.connected(deviceId, peer.deviceName);
    _send(entry.key, MessageType.pairApproved, {
      'token': token,
    }, sessionId: pairing.sessionId);
    onLog?.call('Approved ${peer.deviceName}');
    _notify();
    return true;
  }

  /// Rejects a pending join request and closes the connection.
  bool reject(String deviceId) {
    final entry = _find(deviceId, PeerState.pendingApproval);
    if (entry == null) return false;
    entry.value.approvalTimer?.cancel();
    onLog?.call('Rejected ${entry.value.deviceName}');
    _fail(entry.key, 'pairDenied', 'Join request denied');
    return true;
  }

  /// Removes a device: its token stops working and its connection closes.
  void revoke(String deviceId) {
    pairing.revoke(deviceId);
    final entry = _find(deviceId, PeerState.authenticated);
    if (entry != null) {
      _send(entry.key, MessageType.goodbye, {'reason': 'revoked'});
      _close(entry.key);
    }
    registry.remove(deviceId);
    onLog?.call('Revoked ${_short(deviceId)}');
    _notify();
  }

  void _onConnection(WebSocketChannel channel, String? protocol) {
    onLog?.call('Incoming connection');
    _peers[channel] = _Peer();
    channel.stream.listen(
      (dynamic data) => _onData(channel, data),
      onDone: () => _drop(channel),
      onError: (Object e) {
        onLog?.call('Socket error: $e');
        _drop(channel);
      },
      cancelOnError: true,
    );
  }

  void _drop(WebSocketChannel channel) {
    final peer = _peers.remove(channel);
    if (peer == null) return;
    peer.approvalTimer?.cancel();
    final id = peer.deviceId;
    if (id != null) {
      if (peer.state == PeerState.authenticated) {
        registry.disconnected(id);
        onDeviceLost?.call(id);
      }
      onLog?.call('Peer disconnected: ${peer.deviceName}');
    }
    _notify();
  }

  void _close(WebSocketChannel channel) {
    _drop(channel);
    try {
      channel.sink.close();
    } catch (_) {}
  }

  void _fail(WebSocketChannel channel, String code, String message) {
    _send(channel, MessageType.error, {'code': code, 'message': message});
    _close(channel);
  }

  void _onData(WebSocketChannel channel, dynamic data) {
    if (data is! String) {
      onLog?.call('Ignored non-text frame');
      return;
    }
    try {
      _handle(channel, codec.decode(data));
    } on ProtocolException catch (e) {
      onLog?.call('Rejected message: ${e.code.name}');
      _send(channel, MessageType.error, {
        'code': e.code.name,
        'message': e.message,
      });
    }
  }

  void _handle(WebSocketChannel channel, ProtocolMessage msg) {
    final peer = _peers[channel];
    if (peer == null) return;

    if (msg.type == MessageType.hello) {
      _onHello(channel, peer, msg);
      return;
    }
    if (peer.state == PeerState.connected) {
      _sendError(channel, 'helloRequired', 'Send HELLO first');
      return;
    }
    if (msg.senderDeviceId != peer.deviceId) {
      _sendError(channel, 'senderMismatch', 'Sender does not match HELLO');
      return;
    }

    switch (msg.type) {
      case MessageType.pairRequest:
        _onPairRequest(channel, peer, msg);
      case MessageType.goodbye:
        _close(channel);
      default:
        if (peer.state != PeerState.authenticated) {
          _sendError(channel, 'notAuthenticated', 'Pair with the mesh first');
          return;
        }
        if (msg.sessionId != pairing.sessionId) {
          _sendError(channel, 'badSession', 'Wrong or missing sessionId');
          return;
        }
        _onAuthenticated(channel, msg);
    }
  }

  void _onHello(WebSocketChannel channel, _Peer peer, ProtocolMessage msg) {
    if (peer.state != PeerState.connected) {
      _sendError(channel, 'alreadyIntroduced', 'HELLO already received');
      return;
    }
    final id = msg.senderDeviceId;
    final token = msg.payload['token'];
    final resumed = token is String && pairing.verifyToken(id, token);

    // A live authenticated connection for this device already exists.
    // Only a valid token may take it over, never a bare device ID.
    final existing = _find(id, PeerState.authenticated);
    if (existing != null && existing.key != channel) {
      if (!resumed) {
        _sendError(channel, 'duplicateDevice', 'Device already connected');
        return;
      }
      _send(existing.key, MessageType.goodbye, {'reason': 'replaced'});
      _close(existing.key);
    }

    peer.deviceId = id;
    final name = msg.payload['deviceName'];
    peer.deviceName = name is String ? _clip(name) : 'unknown';
    peer.state = resumed ? PeerState.authenticated : PeerState.helloDone;

    _send(channel, MessageType.hello, {
      'deviceName': deviceName,
      'role': 'coordinator',
      'resumed': resumed,
    }, sessionId: resumed ? pairing.sessionId : null);
    onLog?.call(
      'HELLO from ${peer.deviceName} (${_short(id)})${resumed ? ' [resumed]' : ''}',
    );
    if (resumed) registry.connected(id, peer.deviceName);
    _notify();
  }

  void _onPairRequest(
    WebSocketChannel channel,
    _Peer peer,
    ProtocolMessage msg,
  ) {
    if (peer.state != PeerState.helloDone) {
      _sendError(channel, 'invalidState', 'Cannot pair in this state');
      return;
    }
    final code = msg.payload['code'];
    if (code is! String) {
      _sendError(channel, 'invalidField', 'code must be a string');
      return;
    }
    final handler = onPairRequest;
    if (handler == null) {
      _fail(channel, 'pairRejected', 'Coordinator is not accepting devices');
      return;
    }

    final check = pairing.consumeCode(code);
    if (check != PairingCheck.ok) {
      // Log the precise reason locally; tell the client only "invalid".
      onLog?.call('Pairing failed (${check.name}) from ${peer.deviceName}');
      _fail(channel, 'pairRejected', 'Invalid or expired code');
      return;
    }

    final id = peer.deviceId!;
    final name = msg.payload['deviceName'];
    if (name is String) peer.deviceName = _clip(name);
    peer.state = PeerState.pendingApproval;
    peer.approvalTimer = Timer(approvalTimeout, () => reject(id));
    onLog?.call('Join request from ${peer.deviceName}');
    _notify();
    handler(
      PeerInfo(deviceId: id, deviceName: peer.deviceName, state: peer.state),
    );
  }

  void _onAuthenticated(WebSocketChannel channel, ProtocolMessage msg) {
    switch (msg.type) {
      case MessageType.heartbeat:
        registry.markSeen(msg.senderDeviceId);
        _send(channel, MessageType.heartbeatAck, {
          'seq': msg.payload['seq'],
          'echoTimestamp': msg.timestamp,
        }, sessionId: pairing.sessionId);
      case MessageType.capabilityAdvertisement:
        _onCapabilities(channel, msg);
      case MessageType.taskAccept:
      case MessageType.taskStarted:
      case MessageType.taskResult:
      case MessageType.taskFailed:
        onTaskMessage?.call(msg.senderDeviceId, msg);
      default:
        onLog?.call('Unhandled ${msg.type.wire}');
    }
  }

  void _onCapabilities(WebSocketChannel channel, ProtocolMessage msg) {
    final id = msg.senderDeviceId;
    try {
      final caps = DeviceCapabilities.fromJson(msg.payload);
      if (!registry.setCapabilities(id, caps)) {
        onLog?.call('Capabilities from unknown device ignored');
        return;
      }
      final tasks = caps.supportedTasks.map((t) => t.wire).join(', ');
      onLog?.call(
        'Capabilities from ${_short(id)}: ${tasks.isEmpty ? 'none' : tasks}',
      );
      _notify();
    } on FormatException catch (e) {
      _sendError(channel, 'invalidCapabilities', e.message);
    }
  }

  /// Sends a message to an authenticated device. False if it is not connected.
  bool sendTo(
    String deviceId,
    MessageType type,
    Map<String, dynamic> payload,
  ) {
    final entry = _find(deviceId, PeerState.authenticated);
    if (entry == null) return false;
    _send(entry.key, type, payload, sessionId: pairing.sessionId);
    return true;
  }

  MapEntry<WebSocketChannel, _Peer>? _find(String id, PeerState state) {
    for (final e in _peers.entries) {
      if (e.value.deviceId == id && e.value.state == state) return e;
    }
    return null;
  }

  void _sendError(WebSocketChannel channel, String code, String message) {
    onLog?.call('Error to peer: $code');
    _send(channel, MessageType.error, {'code': code, 'message': message});
  }

  void _send(
    WebSocketChannel channel,
    MessageType type,
    Map<String, dynamic> payload, {
    String? sessionId,
  }) {
    try {
      channel.sink.add(
        codec.encode(
          ProtocolMessage.create(
            type: type,
            senderDeviceId: deviceId,
            sessionId: sessionId,
            payload: payload,
          ),
        ),
      );
    } catch (_) {
      // Channel already closed.
    }
  }

  void _notify() => onPeersChanged?.call();

  String _clip(String s) => s.length > 40 ? s.substring(0, 40) : s;

  String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;
}
