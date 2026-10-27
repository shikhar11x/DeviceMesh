import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/worker_controller.dart';

/// Worker buttons. Selects a record of flags, so RTT updates every 2 s
/// do not rebuild the buttons.
class WorkerActions extends ConsumerWidget {
  const WorkerActions({
    super.key,
    required this.onConnect,
    required this.onPair,
  });

  final VoidCallback onConnect;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (connecting, connected, paired, pairing, heartbeatOn) = ref.watch(
      workerProvider.select(
        (s) => (s.connecting, s.connected, s.paired, s.pairing, s.heartbeatOn),
      ),
    );
    final ctrl = ref.read(workerProvider.notifier);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: (connected || connecting) ? null : onConnect,
          child: Text(connecting ? 'Connecting...' : 'Connect'),
        ),
        FilledButton.tonal(
          onPressed: (connected && !paired && !pairing) ? onPair : null,
          child: Text(pairing ? 'Waiting for approval...' : 'Pair'),
        ),
        OutlinedButton(
          onPressed: paired ? ctrl.toggleHeartbeat : null,
          child: Text(heartbeatOn ? 'Stop heartbeat' : 'Start heartbeat'),
        ),
        OutlinedButton(
          onPressed: connected ? ctrl.disconnect : null,
          child: const Text('Disconnect'),
        ),
      ],
    );
  }
}