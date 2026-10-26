import 'dart:convert';
import 'package:devicemesh/services/protocol/message_type.dart';
import 'package:devicemesh/services/protocol/protocol_codec.dart';
import 'package:devicemesh/services/protocol/protocol_exception.dart';
import 'package:devicemesh/services/protocol/protocol_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = ProtocolCodec(maxControlBytes: 1024);

  ProtocolException? decodeError(String raw) {
    try {
      codec.decode(raw);
    } on ProtocolException catch (e) {
      return e;
    }
    return null;
  }

  test('round-trips a valid message', () {
    final msg = ProtocolMessage.create(
      type: MessageType.heartbeat,
      senderDeviceId: 'device-a',
      sessionId: 'session-1',
      payload: {'seq': 1},
    );
    final decoded = codec.decode(codec.encode(msg));
    expect(decoded.messageId, msg.messageId);
    expect(decoded.type, MessageType.heartbeat);
    expect(decoded.sessionId, 'session-1');
    expect(decoded.payload['seq'], 1);
  });

  test('rejects malformed JSON', () {
    expect(decodeError('{not json')?.code, ProtocolErrorCode.malformedJson);
    expect(decodeError('[1,2]')?.code, ProtocolErrorCode.malformedJson);
  });

  test('rejects unsupported version', () {
    final raw = jsonEncode({
      'protocolVersion': 99,
      'messageId': 'm',
      'type': 'HELLO',
      'senderDeviceId': 'd',
      'timestamp': 1,
      'payload': {},
    });
    expect(decodeError(raw)?.code, ProtocolErrorCode.unsupportedVersion);
  });

  test('rejects unknown type', () {
    final raw = jsonEncode({
      'protocolVersion': 1,
      'messageId': 'm',
      'type': 'RUN_SHELL',
      'senderDeviceId': 'd',
      'timestamp': 1,
      'payload': {},
    });
    expect(decodeError(raw)?.code, ProtocolErrorCode.unknownType);
  });

  test('rejects oversized messages', () {
    final raw = jsonEncode({
      'protocolVersion': 1,
      'messageId': 'm',
      'type': 'HELLO',
      'senderDeviceId': 'd',
      'timestamp': 1,
      'payload': {'blob': 'x' * 2000},
    });
    expect(decodeError(raw)?.code, ProtocolErrorCode.oversized);
  });

  test('rejects missing or invalid fields', () {
    final raw = jsonEncode({
      'protocolVersion': 1,
      'messageId': '',
      'type': 'HELLO',
      'senderDeviceId': 'd',
      'timestamp': 1,
    });
    expect(decodeError(raw)?.code, ProtocolErrorCode.invalidField);
  });
}