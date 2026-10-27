enum TaskType {
  checksum('checksum'),
  imageResize('image_resize');

  const TaskType(this.wire);
  final String wire;

  static TaskType? fromWire(String value) {
    for (final t in TaskType.values) {
      if (t.wire == value) return t;
    }
    return null;
  }
}