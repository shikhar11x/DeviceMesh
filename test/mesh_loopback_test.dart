import 'dart:async';

import 'package:devicemesh/services/networking/mesh_client.dart';
import 'package:devicemesh/services/networking/mesh_server.dart';
import 'package:devicemesh/services/protocol/message_type.dart';
import 'package:devicemesh/services/protocol/protocol_codec.dart';
import 'package:devicemesh/services/protocol/protocol_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  late MeshServer server;
  late int port;
  const codec = ProtocolCodec();

  setUp(() async {
    server = MeshServer(deviceId: 'server-1', deviceName: 'Server');
    port = await server.start(port: 0);
  });

  tearDown(() async {
    await server.stop();
  });

  test('client completes HELLO handshake', () async {
    final client = MeshClient(deviceId: 'client-1', deviceName: 'Client');
    final ok = await client.connect('127.0.0.1', port);
    expect(ok, isTrue);
    expect(client.serverDeviceId, 'server-1');
    expect(server.peerIds, contains('client-1'));
    await client.disconnect();
  });

  test('heartbeat returns a measured latency', () async {
    final latency = Completer<double>();
    final client = MeshClient(
      deviceId: 'client-2',
      deviceName: 'Client',
      onLatency: (ms) {
        if (!latency.isCompleted) latency.complete(ms);
      },
    );
    expect(await client.connect('127.0.0.1', port), isTrue);
    client.sendHeartbeat();
    final ms = await latency.future.timeout(const Duration(seconds: 3));
    expect(ms, greaterThanOrEqualTo(0));
    await client.disconnect();
  });

  test('server rejects messages sent before HELLO', () async {
    final ch = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port'));
    await ch.ready;
    ch.sink.add(codec.encode(ProtocolMessage.create(
      type: MessageType.heartbeat,
      senderDeviceId: 'intruder',
      payload: {'seq': 1},
    )));
    final reply = codec.decode((await ch.stream.first) as String);
    expect(reply.type, MessageType.error);
    expect(server.peerIds, isEmpty);
    await ch.sink.close();
  });

  test('server answers malformed JSON with ERROR and stays alive', () async {
    final ch = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port'));
    await ch.ready;
    ch.sink.add('{bad json');
    final reply = codec.decode((await ch.stream.first) as String);
    expect(reply.type, MessageType.error);
    await ch.sink.close();

    final client = MeshClient(deviceId: 'client-3', deviceName: 'Client');
    expect(await client.connect('127.0.0.1', port), isTrue);
    await client.disconnect();
  });
}