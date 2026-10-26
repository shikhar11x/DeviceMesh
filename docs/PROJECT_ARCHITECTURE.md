# DeviceMesh Architecture

## Topology
Coordinator + workers over local Wi-Fi/hotspot. No cloud backend.

## Layers
presentation (Riverpod + widgets) -> domain (scheduler, task state) -> services (protocol, networking, discovery, persistence).
Scheduler and protocol logic are widget-independent and unit-tested.

## Transport
Dev mode: ws:// (labeled insecure). Production target: WSS with pinned self-signed cert exchanged via QR.

## Task lifecycle
queued -> assigned -> running -> completed | failed | cancelled.
Retry-safe tasks may be reassigned; each attempt has an attemptId.

## Limitations
No remote GPU/RAM/camera sharing. Migration = reassignment of unfinished retry-safe tasks only.