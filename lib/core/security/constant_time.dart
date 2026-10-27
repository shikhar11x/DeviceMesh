import 'dart:convert';

/// Compares two strings without returning early on the first mismatch.
bool constantTimeEquals(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  var diff = x.length ^ y.length;
  final n = x.length < y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}