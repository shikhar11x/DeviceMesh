import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/device_identity.dart';

final deviceIdProvider =
    FutureProvider<String>((ref) => DeviceIdentity.getOrCreateId());

/// Friendly name derived from the stable device ID.
String deviceNameFor(String id) =>
    'Phone-${id.length >= 4 ? id.substring(0, 4) : id}';