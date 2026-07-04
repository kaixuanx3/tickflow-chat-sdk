/// Local per-session read marks — the client side of unread badges.
///
/// The session-list endpoint carries no unread counts; v1 unread is
/// client-derived: a session shows activity when its `updatedAt` is newer
/// than the locally stored last-read instant. The default store is
/// in-memory; hosts that want badges to survive restarts override
/// `chatReadMarksProvider` with a persistent implementation (e.g. backed by
/// `SharedPreferences`).
abstract class ChatReadMarks {
  /// When [sessionId] was last read on this device, or null if never.
  DateTime? lastReadAt(String sessionId);

  /// Records that [sessionId] has been read at [at].
  Future<void> markRead(String sessionId, DateTime at);
}

/// Default store: process-lifetime only.
class InMemoryChatReadMarks implements ChatReadMarks {
  final _marks = <String, DateTime>{};

  @override
  DateTime? lastReadAt(String sessionId) => _marks[sessionId];

  @override
  Future<void> markRead(String sessionId, DateTime at) async {
    _marks[sessionId] = at;
  }
}
