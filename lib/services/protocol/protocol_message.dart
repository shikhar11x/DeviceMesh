import 'package:uuid/uuid.dart';
import 'message_type.dart';

class ProtocolMessage {
  const ProtocolMessage({
    required this.protocolVersion,
    required this.messageId,
    required this.type,
    required this.senderDeviceId,
    required this.timestamp,
    this.sessionId,
    this.payload = const {},
  });

  static const int currentVersion = 1;
  static const Uuid _uuid = Uuid();

  final int protocolVersion;
  final String messageId;
  final MessageType type;
  final String? sessionId;
  final String senderDeviceId;
  final int timestamp; // epoch milliseconds (UTC)
  final Map<String, dynamic> payload;

  factory ProtocolMessage.create({
    required MessageType type,
    required String senderDeviceId,
    String? sessionId,
    Map<String, dynamic> payload = const {},
  }) {
    return ProtocolMessage(
      protocolVersion: currentVersion,
      messageId: _uuid.v4(),
      type: type,
      sessionId: sessionId,
      senderDeviceId: senderDeviceId,
      timestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
      payload: payload,
    );
  }

  Map<String, dynamic> toJson() => {
        'protocolVersion': protocolVersion,
        'messageId': messageId,
        'type': type.wire,
        if (sessionId != null) 'sessionId': sessionId,
        'senderDeviceId': senderDeviceId,
        'timestamp': timestamp,
        'payload': payload,
      };
}