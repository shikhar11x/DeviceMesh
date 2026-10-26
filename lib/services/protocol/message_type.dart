enum MessageType {
  hello('HELLO'),
  pairRequest('PAIR_REQUEST'),
  pairApproved('PAIR_APPROVED'),
  capabilityAdvertisement('CAPABILITY_ADVERTISEMENT'),
  capabilityUpdate('CAPABILITY_UPDATE'),
  heartbeat('HEARTBEAT'),
  heartbeatAck('HEARTBEAT_ACK'),
  taskSubmit('TASK_SUBMIT'),
  taskAssign('TASK_ASSIGN'),
  taskAccept('TASK_ACCEPT'),
  taskStarted('TASK_STARTED'),
  taskProgress('TASK_PROGRESS'),
  taskResult('TASK_RESULT'),
  taskFailed('TASK_FAILED'),
  taskCancel('TASK_CANCEL'),
  taskReassign('TASK_REASSIGN'),
  deviceDisconnected('DEVICE_DISCONNECTED'),
  error('ERROR'),
  goodbye('GOODBYE');

  const MessageType(this.wire);
  final String wire;

  static MessageType? fromWire(String value) {
    for (final t in MessageType.values) {
      if (t.wire == value) return t;
    }
    return null;
  }
}