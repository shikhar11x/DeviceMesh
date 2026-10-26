import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../protocol/message_type.dart';
import '../protocol/protocol_codec.dart';
import '../protocol/protocol_exception.dart';
import '../protocol/protocol_message.dart';

/// DEV-MODE client: plain ws://, no authentication yet.
class MeshClient {
  MeshClient({
    required this.deviceId,
    required this.deviceName,
    this.codec = const ProtocolCodec(),
    this.onLog,
    this.onLatency,
    this.onDisconnected,
  });

  final String deviceId;
  final String deviceName;
  final ProtocolCodec codec;
  final void Function(String message)? onLog;
  final void Function(double milliseconds)? onLatency;
  final void Function()? onDisconnected;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeatTimer;
  Completer<void>? _helloDone;
  final Stopwatch _clock = Stopwatch()..start(); // monotonic
  final Map<int, int> _pending = {}; // seq -> sent micros
  int _seq = 0;

  String? serverDeviceId;

  bool get isConnected => _channel != null;

  Future<bool> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await disconnect();

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

    _send(MessageType.hello, {'deviceName': deviceName, 'role': 'worker'});

    try {
      await _helloDone!.future.timeout(timeout);
    } catch (_) {
      onLog?.call('No HELLO reply from server');
      await disconnect();
      return false;
    }
    return true;
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
    if (_channel == null) return;
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
    _pending.clear();
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
          onLog?.call('HELLO from ${msg.payload['deviceName']}');
          if (!(_helloDone?.isCompleted ?? true)) _helloDone!.complete();
        case MessageType.heartbeatAck:
          final seq = msg.payload['seq'];
          if (seq is int) {
            final sent = _pending.remove(seq);
            if (sent != null) {
              onLatency?.call((_clock.elapsedMicroseconds - sent) / 1000.0);
            }
          }
        case MessageType.error:
          onLog?.call('Server error: ${msg.payload['message']}');
        case MessageType.goodbye:
          onLog?.call('Server said GOODBYE');
        default:
          onLog?.call('Unhandled ${msg.type.wire}');
      }
    } on ProtocolException catch (e) {
      onLog?.call('Bad message: ${e.message}');
    }
  }

  void _send(MessageType type, Map<String, dynamic> payload) {
    _channel?.sink.add(codec.encode(ProtocolMessage.create(
      type: type,
      senderDeviceId: deviceId,
      payload: payload,
    )));
  }
}