import 'package:meta/meta.dart';

import 'chat_role.dart';

@immutable
class ChatSession {
  const ChatSession({required this.id, required this.mode, required this.status});

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        mode: SessionMode.fromWire(json['mode'] as String? ?? ''),
        status: SessionStatus.fromWire(json['status'] as String? ?? ''),
      );

  final String id;
  final SessionMode mode;
  final SessionStatus status;

  ChatSession copyWith({SessionMode? mode, SessionStatus? status}) =>
      ChatSession(id: id, mode: mode ?? this.mode, status: status ?? this.status);

  @override
  bool operator ==(Object other) =>
      other is ChatSession && other.id == id && other.mode == mode && other.status == status;

  @override
  int get hashCode => Object.hash(id, mode, status);

  @override
  String toString() => 'ChatSession($id, $mode, $status)';
}
