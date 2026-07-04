import 'package:meta/meta.dart';

import 'chat_role.dart';

@immutable
class ChatSession {
  const ChatSession({
    required this.id,
    required this.mode,
    required this.status,
    this.updatedAt,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'] as String,
    mode: SessionMode.fromWire(json['mode'] as String? ?? ''),
    status: SessionStatus.fromWire(json['status'] as String? ?? ''),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
  );

  /// Placeholder for attaching to a session by id before server state is
  /// known (a fresh session is `ai`/`open`; history hydration is Phase 1).
  factory ChatSession.stub(String id) =>
      ChatSession(id: id, mode: SessionMode.ai, status: SessionStatus.open);

  final String id;
  final SessionMode mode;
  final SessionStatus status;

  /// Last activity, UTC — drives inbox ordering and labels. Null when the
  /// wire (or a stub) didn't carry it.
  final DateTime? updatedAt;

  ChatSession copyWith({SessionMode? mode, SessionStatus? status}) =>
      ChatSession(
        id: id,
        mode: mode ?? this.mode,
        status: status ?? this.status,
        updatedAt: updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is ChatSession &&
      other.id == id &&
      other.mode == mode &&
      other.status == status &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, mode, status, updatedAt);

  @override
  String toString() => 'ChatSession($id, $mode, $status)';
}
