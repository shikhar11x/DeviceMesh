enum ProtocolErrorCode {
  malformedJson,
  oversized,
  unsupportedVersion,
  unknownType,
  invalidField,
}

class ProtocolException implements Exception {
  const ProtocolException(this.code, this.message);
  final ProtocolErrorCode code;
  final String message;

  @override
  String toString() => 'ProtocolException(${code.name}): $message';
}