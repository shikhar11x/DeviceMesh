import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';
import '../../features/devices/domain/device_capabilities.dart';
import '../protocol/message_type.dart';
import '../protocol/protocol_codec.dart';
import '../protocol/protocol_exception.dart';
import '../protocol/protocol_message.dart';

enum PairOutcome { approved, rejected, denied, timedOut, disconnected }

/// DEV-MODE client: plain ws://, pairing by code, token-based resume.
class MeshClient {
  MeshClient({
    required this.deviceId,
    required this.deviceName,
    this.codec = const ProtocolCodec(),
    this.capabilities,
    this.onLog,
    this.onLatency,
    this.onDisconnected,
    this.onTaskMessage,
  });

  final String deviceId;
  final String deviceName;
  final ProtocolCodec codec;

  /// Sent to the coordinator right after pairing or session resume.
  final DeviceCapabilities? capabilities;
  final void Function(String message)? onLog;
  final void Function(double milliseconds)? onLatency;
  final void Function()? onDisconnected;

  /// TASK_ASSIGN / TASK_CANCEL from the coordinator, already checked to
  /// belong to this paired session.
  final void Function(ProtocolMessage message)? onTaskMessage;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeatTimer;
  Completer<void>? _helloDone;
  Completer<PairOutcome>? _pairDone;
  String? _offeredToken;
  final Stopwatch _clock = Stopwatch()..start(); // monotonic
  final Map<int, int> _pending = {}; // seq -> sent micros
  int _seq = 0;

  String? serverDeviceId;

  /// Set after approval or a successful token resume.
  String? sessionId;

  /// Secret issued by the coordinator. Keep it only in memory/secure storage.
  String? sessionToken;

  bool get isConnected => _channel != null;
  bool get isPaired => _channel != null && sessionId != null;

  Future<bool> connect(
    String host,
    int port, {
    String? resumeToken,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await disconnect();
    _offeredToken = resumeToken;

    final channel = WebSocketChannel.connect(Uri.parse('ws://$host:$port'));
    try {
      await channel.ready.timeout(timeout);
    } catch (e) {
      onLog?.call('Connect failed: $e');
      try {
        channel.sink.close();
      } catch (_) {}
      return false;
    }

    _channel = channel;
    _helloDone = Completer<void>();
    _sub = channel.stream.listen(
      _onData,
      onDone: _onClosed,
      onError: (Object e) {
        onLog?.call('Socket error: $e');
        _onClosed();
      },
      cancelOnError: true,
    );

    _send(MessageType.hello, {
      'deviceName': deviceName,
      'role': 'worker',
      'token': ?resumeToken,
    });

    try {
      await _helloDone!.future.timeout(timeout);
    } catch (_) {
      onLog?.call('No HELLO reply from server');
      await disconnect();
      return false;
    }
    return true;
  }

  /// Sends the pairing code and waits for the coordinator's decision.
  Future<PairOutcome> pair(
    String code, {
    Duration timeout = const Duration(seconds: 75),
  }) async {
    if (_channel == null) return PairOutcome.disconnected;
    final done = Completer<PairOutcome>();
    _pairDone = done;
    _send(MessageType.pairRequest, {'code': code, 'deviceName': deviceName});
    try {
      return await done.future.timeout(timeout);
    } on TimeoutException {
      return PairOutcome.timedOut;
    } finally {
      if (identical(_pairDone, done)) _pairDone = null;
    }
  }

  void startHeartbeat([Duration interval = const Duration(seconds: 2)]) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(interval, (_) => sendHeartbeat());
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void sendHeartbeat() {
    if (_channel == null || sessionId == null) return;
    final seq = ++_seq;
    if (_pending.length > 50) _pending.remove(_pending.keys.first);
    _pending[seq] = _clock.elapsedMicroseconds;
    _send(MessageType.heartbeat, {'seq': seq});
  }

  Future<void> disconnect() async {
    final ch = _channel;
    if (ch == null) return;
    try {
      _send(MessageType.goodbye, {});
    } catch (_) {}
    _cleanup();
    try {
      await ch.sink.close();
    } catch (_) {}
  }

  void _cleanup() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _sub?.cancel();
    _sub = null;
    _channel = null;
    sessionId = null;
    _pending.clear();
    _completePair(PairOutcome.disconnected);
  }

  void _completePair(PairOutcome outcome) {
    final c = _pairDone;
    if (c != null && !c.isCompleted) c.complete(outcome);
  }

  void _onClosed() {
    if (_channel == null) return; // already cleaned up
    _cleanup();
    onLog?.call('Connection closed');
    onDisconnected?.call();
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    try {
      final msg = codec.decode(data);
      switch (msg.type) {
        case MessageType.hello:
          serverDeviceId = msg.senderDeviceId;
          final resumed = msg.payload['resumed'] == true;
          if (resumed && msg.sessionId != null) {
            sessionId = msg.sessionId;
            sessionToken = _offeredToken;
            onLog?.call('Session resumed');
            _advertise();
          } else {
            sessionToken = null;
          }
          onLog?.call('HELLO from ${msg.payload['deviceName']}');
          if (!(_helloDone?.isCompleted ?? true)) _helloDone!.complete();
        case MessageType.pairApproved:
          final token = msg.payload['token'];
          if (token is String && msg.sessionId != null) {
            sessionId = msg.sessionId;
            sessionToken = token;
            _advertise();
            _completePair(PairOutcome.approved);
          } else {
            onLog?.call('Malformed PAIR_APPROVED');
            _completePair(PairOutcome.rejected);
          }
        case MessageType.heartbeatAck:
          final seq = msg.payload['seq'];
          if (seq is int) {
            final sent = _pending.remove(seq);
            if (sent != null) {
              onLatency?.call((_clock.elapsedMicroseconds - sent) / 1000.0);
            }
          }
        case MessageType.error:
          final code = msg.payload['code'];
          onLog?.call('Server error: ${msg.payload['message']}');
          if (code == 'pairRejected') _completePair(PairOutcome.rejected);
          if (code == 'pairDenied') _completePair(PairOutcome.denied);
        case MessageType.taskAssign:
        case MessageType.taskCancel:
          if (isPaired && msg.sessionId == sessionId) {
            onTaskMessage?.call(msg);
          } else {
            onLog?.call('Ignored ${msg.type.wire} outside the session');
          }
        case MessageType.goodbye:
          onLog?.call('Server said GOODBYE (${msg.payload['reason'] ?? '-'})');
        default:
          onLog?.call('Unhandled ${msg.type.wire}');
      }
    } on ProtocolException catch (e) {
      onLog?.call('Bad message: ${e.message}');
    }
  }

  static const Set<MessageType> _workerTaskTypes = {
    MessageType.taskAccept,
    MessageType.taskStarted,
    MessageType.taskResult,
    MessageType.taskFailed,
  };

  /// Worker -> coordinator task messages. Only a paired client may send them.
  void sendTask(MessageType type, Map<String, dynamic> payload) {
    if (!_workerTaskTypes.contains(type)) {
      throw ArgumentError.value(type, 'type', 'not a worker task message');
    }
    if (!isPaired) return;
    _send(type, payload);
  }

  void _advertise() {
    final caps = capabilities;
    if (caps == null) return;
    _send(MessageType.capabilityAdvertisement, caps.toJson());
  }

  void _send(MessageType type, Map<String, dynamic> payload) {
    _channel?.sink.add(codec.encode(ProtocolMessage.create(
      type: type,
      senderDeviceId: deviceId,
      sessionId: sessionId,
      payload: payload,
    )));
  }
}