int _seq = 0;

/// Locally-unique tag for an optimistic message: reconciles the echo with
/// its server copy and doubles as the idempotency key on retries.
String newClientTag() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_seq++}';
