import 'package:meta/meta.dart';

import 'chat_role.dart';

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.status = MessageStatus.sent,
    this.clientTag,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String? ?? '',
    sessionId: json['sessionId'] as String? ?? '',
    role: ChatRole.fromWire(json['role'] as String? ?? ''),
    content: json['content'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ??
        DateTime.utc(1970),
  );

  /// Server id; empty until the server has acknowledged the message.
  final String id;
  final String sessionId;
  final ChatRole role;
  final String content;

  /// UTC; render in the device locale.
  final DateTime createdAt;

  // Client-only fields — never serialized outbound.
  final MessageStatus status;

  /// Reconciles an optimistic echo with its server copy; doubles as the
  /// idempotency key on retries.
  final String? clientTag;

  ChatMessage copyWith({String? content, MessageStatus? status}) => ChatMessage(
    id: id,
    sessionId: sessionId,
    role: role,
    content: content ?? this.content,
    createdAt: createdAt,
    status: status ?? this.status,
    clientTag: clientTag,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.id == id &&
      other.sessionId == sessionId &&
      other.role == role &&
      other.content == content &&
      other.createdAt == createdAt &&
      other.status == status &&
      other.clientTag == clientTag;

  @override
  int get hashCode =>
      Object.hash(id, sessionId, role, content, createdAt, status, clientTag);

  @override
  String toString() => 'ChatMessage($role, $status, ${content.length} chars)';
}
