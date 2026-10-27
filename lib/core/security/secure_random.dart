import 'dart:convert';
import 'dart:math';

/// Cryptographically secure random values (Random.secure()).
class SecureRandom {
  static final Random _rng = Random.secure();

  /// URL-safe random token without padding.
  static String token([int bytes = 32]) {
    final data = List<int>.generate(bytes, (_) => _rng.nextInt(256));
    return base64UrlEncode(data).replaceAll('=', '');
  }

  /// Numeric code such as a 6-digit pairing code.
  static String numericCode([int digits = 6]) {
    final buf = StringBuffer();
    for (var i = 0; i < digits; i++) {
      buf.write(_rng.nextInt(10));
    }
    return buf.toString();
  }
}