import 'dart:async';

import 'package:devicemesh/services/networking/mesh_client.dart';
import 'package:devicemesh/services/networking/mesh_server.dart';
import 'package:devicemesh/services/protocol/message_type.dart';
import 'package:devicemesh/services/protocol/protocol_codec.dart';
import 'package:devicemesh/services/protocol/protocol_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const codec = ProtocolCodec();

/// Minimal raw WebSocket peer for sending hand-made (even invalid) frames.
class RawPeer {
  RawPeer._(this.channel);

  final WebSocketChannel channel;
  final List<ProtocolMessage> _queue = [];
  Completer<ProtocolMessage>? _waiter;

  static Future<RawPeer> open(int port) async {
    final ch = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port'));
    await ch.ready;
    final peer = RawPeer._(ch);
    ch.stream.listen((dynamic d) {
      final m = codec.decode(d as String);
      final w = peer._waiter;
      if (w != null) {
        peer._waiter = null;
        w.complete(m);
      } else {
        peer._queue.add(m);
      }
    }, onError: (Object _) {}, onDone: () {});
    return peer;
  }

  void sendRaw(String text) => channel.sink.add(text);

  void send(MessageType type, {Map<String, dynamic> payload = const {}}) {
    channel.sink.add(codec.encode(ProtocolMessage.create(
      type: type,
      senderDeviceId: 'raw-peer',
      payload: payload,
    )));
  }

  Future<ProtocolMessage> next() {
    if (_queue.isNotEmpty) return Future.value(_queue.removeAt(0));
    final c = Completer<ProtocolMessage>();
    _waiter = c;
    return c.future.timeout(const Duration(seconds: 3));
  }

  Future<void> close() => channel.sink.close();
}

void main() {
  late MeshServer server;
  late int port;

  setUp(() async {
    server = MeshServer(deviceId: 'server-1', deviceName: 'Server');
    server.onPairRequest = (r) => server.approve(r.deviceId);
    port = await server.start(port: 0);
  });

  tearDown(() async {
    await server.stop();
  });

  Future<MeshClient> pairedClient(String id) async {
    final c = MeshClient(deviceId: id, deviceName: 'Client $id');
    expect(await c.connect('127.0.0.1', port), isTrue);
    expect(await c.pair(server.pairing.issueCode()), PairOutcome.approved);
    return c;
  }

  test('HELLO succeeds but the client is not authenticated', () async {
    final c = MeshClient(deviceId: 'c-1', deviceName: 'Client');
    expect(await c.connect('127.0.0.1', port), isTrue);
    expect(c.serverDeviceId, 'server-1');
    expect(c.isPaired, isFalse);
    expect(server.pairedPeers, isEmpty);
    await c.disconnect();
  });

  test('valid code + approval pairs the device', () async {
    final c = await pairedClient('c-2');
    expect(c.isPaired, isTrue);
    expect(c.sessionId, server.pairing.sessionId);
    expect(c.sessionToken, isNotNull);
    expect(server.pairedPeers.map((p) => p.deviceId), contains('c-2'));
    await c.disconnect();
  });

  test('wrong code is rejected', () async {
    final code = server.pairing.issueCode();
    final wrong = code == '000000' ? '111111' : '000000';
    final c = MeshClient(deviceId: 'c-3', deviceName: 'Client');
    expect(await c.connect('127.0.0.1', port), isTrue);
    expect(await c.pair(wrong), PairOutcome.rejected);
    expect(server.pairedPeers, isEmpty);
    await c.disconnect();
  });

  test('a code can only be used once', () async {
    final code = server.pairing.issueCode();
    final a = MeshClient(deviceId: 'c-4a', deviceName: 'A');
    expect(await a.connect('127.0.0.1', port), isTrue);
    expect(await a.pair(code), PairOutcome.approved);

    final b = MeshClient(deviceId: 'c-4b', deviceName: 'B');
    expect(await b.connect('127.0.0.1', port), isTrue);
    expect(await b.pair(code), PairOutcome.rejected);

    await a.disconnect();
    await b.disconnect();
  });

  test('operator can deny a join request', () async {
    server.onPairRequest = (r) => server.reject(r.deviceId);
    final c = MeshClient(deviceId: 'c-5', deviceName: 'Client');
    expect(await c.connect('127.0.0.1', port), isTrue);
    expect(await c.pair(server.pairing.issueCode()), PairOutcome.denied);
    expect(server.pairedPeers, isEmpty);
    await c.disconnect();
  });

  test('heartbeat returns a measured latency after pairing', () async {
    final latency = Completer<double>();
    final c = MeshClient(
      deviceId: 'c-6',
      deviceName: 'Client',
      onLatency: (ms) {
        if (!latency.isCompleted) latency.complete(ms);
      },
    );
    expect(await c.connect('127.0.0.1', port), isTrue);
    expect(await c.pair(server.pairing.issueCode()), PairOutcome.approved);
    c.sendHeartbeat();
    final ms = await latency.future.timeout(const Duration(seconds: 3));
    expect(ms, greaterThanOrEqualTo(0));
    await c.disconnect();
  });

  test('heartbeat before pairing is rejected', () async {
    final raw = await RawPeer.open(port);
    raw.send(MessageType.hello, payload: {'deviceName': 'raw'});
    expect((await raw.next()).type, MessageType.hello);
    raw.send(MessageType.heartbeat, payload: {'seq': 1});
    final reply = await raw.next();
    expect(reply.type, MessageType.error);
    expect(reply.payload['code'], 'notAuthenticated');
    expect(server.pairedPeers, isEmpty);
    await raw.close();
  });

  test('message before HELLO is rejected', () async {
    final raw = await RawPeer.open(port);
    raw.send(MessageType.heartbeat, payload: {'seq': 1});
    final reply = await raw.next();
    expect(reply.type, MessageType.error);
    expect(reply.payload['code'], 'helloRequired');
    await raw.close();
  });

  test('malformed JSON gets ERROR and the server stays alive', () async {
    final raw = await RawPeer.open(port);
    raw.sendRaw('{bad json');
    expect((await raw.next()).type, MessageType.error);
    await raw.close();

    final c = await pairedClient('c-7');
    expect(c.isPaired, isTrue);
    await c.disconnect();
  });

  test('a paired device can resume with its token, no code needed', () async {
    final c1 = await pairedClient('c-8');
    final token = c1.sessionToken!;
    await c1.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final c2 = MeshClient(deviceId: 'c-8', deviceName: 'Client');
    expect(await c2.connect('127.0.0.1', port, resumeToken: token), isTrue);
    expect(c2.isPaired, isTrue);
    expect(c2.sessionId, server.pairing.sessionId);
    await c2.disconnect();
  });

  test('a bogus token does not resume a session', () async {
    final c = MeshClient(deviceId: 'c-9', deviceName: 'Client');
    expect(await c.connect('127.0.0.1', port, resumeToken: 'bogus'), isTrue);
    expect(c.isPaired, isFalse);
    await c.disconnect();
  });

  test('a revoked device cannot resume', () async {
    final c1 = await pairedClient('c-10');
    final token = c1.sessionToken!;
    server.revoke('c-10');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await c1.disconnect();

    final c2 = MeshClient(deviceId: 'c-10', deviceName: 'Client');
    expect(await c2.connect('127.0.0.1', port, resumeToken: token), isTrue);
    expect(c2.isPaired, isFalse);
    await c2.disconnect();
  });
}