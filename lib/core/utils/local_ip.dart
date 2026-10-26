import 'dart:io';

class LocalIp {
  /// Returns entries like "wlan0 192.168.1.5". Works for Wi-Fi and hotspot
  /// interfaces without needing extra permissions.
  static Future<List<String>> findAll() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final result = <String>[];
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) {
          result.add('${iface.name} ${addr.address}');
        }
      }
    }
    return result;
  }
}