import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../protocol/message_type.dart';
import '../protocol/protocol_codec.dart';
import '../protocol/protocol_exception.dart';
import '../protocol/protocol_message.dart';

/// DEV-MODE server: plain ws://, no authentication yet.
class MeshServer {
  MeshServer({
    required this.deviceId,
    required this.deviceName,
    this.codec = const ProtocolCodec(),
    this.onLog,
  });

  final String deviceId;
  final String deviceName;
  final ProtocolCodec codec;
  final void Function(String message)? onLog;

  HttpServer? _server;
  final Map<WebSocketChannel, String> _peers = {};

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  List<String> get peerIds => _peers.values.toList();

  /// Pass port 0 to let the OS choose a free port (used in tests).
  Future<int> start({int port = 8080}) async {
    if (_server != null) return _server!.port;
    final handler = webSocketHandler(_onConnection);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    onLog?.call('Server listening on port ${_server!.port}');
    return _server!.port;
  }

  Future<void> stop() async {
    final channels = _peers.keys.toList();
    _peers.clear();
    for (final ch in channels) {
      try {
        _send(ch, MessageType.goodbye, {});
        await ch.sink.close();
      } catch (_) {}
    }
    await _server?.close(force: true);
    _server = null;
    onLog?.call('Server stopped');
  }

  void _onConnection(WebSocketChannel channel, String? protocol) {
    onLog?.call('Incoming connection');
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
    final id = _peers.remove(channel);
    if (id != null) onLog?.call('Peer disconnected: ${_short(id)}');
  }

  void _onData(WebSocketChannel channel, dynamic data) {
    if (data is! String) {
      onLog?.call('Ignored non-text frame');
      return;
    }
    try {
      final msg = codec.decode(data);
      _handle(channel, msg);
    } on ProtocolException catch (e) {
      onLog?.call('Rejected message: ${e.code.name}');
      _send(channel, MessageType.error,
          {'code': e.code.name, 'message': e.message});
    }
  }

  void _handle(WebSocketChannel channel, ProtocolMessage msg) {
    // A peer must introduce itself before anything else is accepted.
    if (msg.type != MessageType.hello && !_peers.containsKey(channel)) {
      onLog?.call('Rejected ${msg.type.wire} before HELLO');
      _send(channel, MessageType.error,
          {'code': 'helloRequired', 'message': 'Send HELLO first'});
      return;
    }

    switch (msg.type) {
      case MessageType.hello:
        _peers[channel] = msg.senderDeviceId;
        onLog?.call(
            'HELLO from ${msg.payload['deviceName']} (${_short(msg.senderDeviceId)})');
        _send(channel, MessageType.hello,
            {'deviceName': deviceName, 'role': 'coordinator'});
      case MessageType.heartbeat:
        _send(channel, MessageType.heartbeatAck,
            {'seq': msg.payload['seq'], 'echoTimestamp': msg.timestamp});
      case MessageType.goodbye:
        _drop(channel);
        channel.sink.close();
      default:
        onLog?.call('Unhandled ${msg.type.wire}');
    }
  }

  void _send(WebSocketChannel channel, MessageType type,
      Map<String, dynamic> payload) {
    channel.sink.add(codec.encode(ProtocolMessage.create(
      type: type,
      senderDeviceId: deviceId,
      payload: payload,
    )));
  }

  String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;
}