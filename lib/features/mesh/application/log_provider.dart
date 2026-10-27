import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/format.dart';

/// In-memory log for the debug screen. Never put secrets in here.
class LogNotifier extends Notifier<List<String>> {
  static const int _maxLines = 100;

  @override
  List<String> build() => const [];

  void add(String message) {
    final next = ['${formatHms(DateTime.now())}  $message', ...state];
    state = next.length > _maxLines ? next.sublist(0, _maxLines) : next;
  }

  void clear() => state = const [];
}

final logProvider =
    NotifierProvider<LogNotifier, List<String>>(LogNotifier.new);