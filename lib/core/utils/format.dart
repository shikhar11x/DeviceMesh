/// 24-hour HH:MM:SS.
String formatHms(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

/// First 8 characters of an ID. For display only.
String shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

String _two(int n) => n.toString().padLeft(2, '0');