enum TaskState {
  queued,
  assigned,
  running,
  completed,
  failed,
  cancelled;

  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;

  /// Handed to a worker and not finished yet.
  bool get isActive => this == assigned || this == running;
}

/// How a stored result was checked. Rejected results are never stored.
enum ResultValidation { formatOnly, spotChecked }