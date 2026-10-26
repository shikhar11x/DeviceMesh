import 'dart:convert';
import 'message_type.dart';
import 'protocol_exception.dart';
import 'protocol_message.dart';

/// Encodes/decodes JSON control messages. Large binary data must use
/// separate bounded chunk frames (added in a later step), never this codec.
class ProtocolCodec {
  const ProtocolCodec({this.maxControlBytes = 64 * 1024});

  final int maxControlBytes;

  String encode(ProtocolMessage message) {
    final raw = jsonEncode(message.toJson());
    if (utf8.encode(raw).length > maxControlBytes) {
      throw const ProtocolException(
          ProtocolErrorCode.oversized, 'Outgoing message exceeds size limit');
    }
    return raw;
  }

  ProtocolMessage decode(String raw) {
    if (utf8.encode(raw).length > maxControlBytes) {
      throw const ProtocolException(
          ProtocolErrorCode.oversized, 'Incoming message exceeds size limit');
    }

    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const ProtocolException(
          ProtocolErrorCode.malformedJson, 'Message is not valid JSON');
    }
    if (json is! Map<String, dynamic>) {
      throw const ProtocolException(
          ProtocolErrorCode.malformedJson, 'Message must be a JSON object');
    }

    final version = json['protocolVersion'];
    if (version is! int) {
      throw const ProtocolException(
          ProtocolErrorCode.invalidField, 'protocolVersion must be an integer');
    }
    if (version != ProtocolMessage.currentVersion) {
      throw ProtocolException(ProtocolErrorCode.unsupportedVersion,
          'Unsupported protocol version $version');
    }

    final messageId = _requireString(json, 'messageId');
    final senderDeviceId = _requireString(json, 'senderDeviceId');

    final typeRaw = _requireString(json, 'type');
    final type = MessageType.fromWire(typeRaw);
    if (type == null) {
      throw const ProtocolException(
          ProtocolErrorCode.unknownType, 'Unknown message type');
    }

    final timestamp = json['timestamp'];
    if (timestamp is! int) {
      throw const ProtocolException(
          ProtocolErrorCode.invalidField, 'timestamp must be an integer');
    }

    final sessionId = json['sessionId'];
    if (sessionId != null && sessionId is! String) {
      throw const ProtocolException(
          ProtocolErrorCode.invalidField, 'sessionId must be a string');
    }

    final payload = json['payload'] ?? <String, dynamic>{};
    if (payload is! Map<String, dynamic>) {
      throw const ProtocolException(
          ProtocolErrorCode.invalidField, 'payload must be an object');
    }

    return ProtocolMessage(
      protocolVersion: version,
      messageId: messageId,
      type: type,
      sessionId: sessionId as String?,
      senderDeviceId: senderDeviceId,
      timestamp: timestamp,
      payload: payload,
    );
  }

  String _requireString(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v is! String || v.isEmpty || v.length > 128) {
      throw ProtocolException(
          ProtocolErrorCode.invalidField, '$key must be a non-empty string');
    }
    return v;
  }
}