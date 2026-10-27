import 'package:devicemesh/services/networking/pairing_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late PairingManager manager;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    manager = PairingManager(
      codeTtl: const Duration(minutes: 2),
      maxFailedAttempts: 3,
      clock: () => now,
    );
  });

  test('issues a 6-digit numeric code', () {
    final code = manager.issueCode();
    expect(code, matches(RegExp(r'^\d{6}$')));
    expect(manager.activeCode, code);
  });

  test('correct code works once, then is consumed', () {
    final code = manager.issueCode();
    expect(manager.consumeCode(code), PairingCheck.ok);
    expect(manager.consumeCode(code), PairingCheck.noActiveCode);
  });

  test('code expires after the TTL', () {
    final code = manager.issueCode();
    now = now.add(const Duration(minutes: 3));
    expect(manager.consumeCode(code), PairingCheck.expired);
    expect(manager.consumeCode(code), PairingCheck.noActiveCode);
    expect(manager.activeCode, isNull);
  });

  test('locks after too many wrong attempts', () {
    final code = manager.issueCode();
    final wrong = code == '000000' ? '111111' : '000000';
    expect(manager.consumeCode(wrong), PairingCheck.wrong);
    expect(manager.consumeCode(wrong), PairingCheck.wrong);
    expect(manager.consumeCode(wrong), PairingCheck.locked);
    expect(manager.consumeCode(code), PairingCheck.noActiveCode);
  });

  test('issuing a new code invalidates the old one', () {
    final first = manager.issueCode();
    final second = manager.issueCode();
    if (first != second) {
      expect(manager.consumeCode(first), PairingCheck.wrong);
    }
    expect(manager.consumeCode(second), PairingCheck.ok);
  });

  test('tokens are per device and can be revoked', () {
    final t = manager.issueToken('dev-a');
    expect(manager.verifyToken('dev-a', t), isTrue);
    expect(manager.verifyToken('dev-b', t), isFalse);
    expect(manager.verifyToken('dev-a', 'bogus'), isFalse);
    manager.revoke('dev-a');
    expect(manager.verifyToken('dev-a', t), isFalse);
    expect(manager.isPaired('dev-a'), isFalse);
  });
}