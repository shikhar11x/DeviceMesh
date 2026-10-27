import '../../core/security/constant_time.dart';
import '../../core/security/secure_random.dart';

enum PairingCheck { ok, noActiveCode, expired, wrong, locked }

/// Coordinator-side pairing state: one session, one active single-use code,
/// and per-device session tokens. Pure Dart, unit-testable.
class PairingManager {
  PairingManager({
    this.codeTtl = const Duration(minutes: 2),
    this.maxFailedAttempts = 5,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final Duration codeTtl;
  final int maxFailedAttempts;
  final DateTime Function() _now;

  final String sessionId = SecureRandom.token(16);

  String? _code;
  DateTime? _expiresAt;
  int _failed = 0;
  final Map<String, String> _tokens = {};

  /// Creates a fresh code and invalidates the previous one.
  String issueCode() {
    _code = SecureRandom.numericCode();
    _expiresAt = _now().add(codeTtl);
    _failed = 0;
    return _code!;
  }

  String? get activeCode {
    final exp = _expiresAt;
    if (_code != null && exp != null && !_now().isBefore(exp)) {
      _clearCode();
    }
    return _code;
  }

  DateTime? get codeExpiresAt => activeCode == null ? null : _expiresAt;

  /// Checks a candidate code. A correct code is consumed (single use).
  PairingCheck consumeCode(String candidate) {
    final code = _code;
    final exp = _expiresAt;
    if (code == null || exp == null) return PairingCheck.noActiveCode;
    if (!_now().isBefore(exp)) {
      _clearCode();
      return PairingCheck.expired;
    }
    if (constantTimeEquals(code, candidate)) {
      _clearCode();
      return PairingCheck.ok;
    }
    _failed++;
    if (_failed >= maxFailedAttempts) {
      _clearCode();
      return PairingCheck.locked;
    }
    return PairingCheck.wrong;
  }

  String issueToken(String deviceId) {
    final token = SecureRandom.token();
    _tokens[deviceId] = token;
    return token;
  }

  bool verifyToken(String deviceId, String token) {
    final t = _tokens[deviceId];
    return t != null && constantTimeEquals(t, token);
  }

  bool isPaired(String deviceId) => _tokens.containsKey(deviceId);

  void revoke(String deviceId) => _tokens.remove(deviceId);

  void _clearCode() {
    _code = null;
    _expiresAt = null;
    _failed = 0;
  }
}