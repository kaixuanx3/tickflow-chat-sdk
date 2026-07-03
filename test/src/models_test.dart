import 'package:flutter_test/flutter_test.dart';
import 'package:tickflow_chat/tickflow_chat.dart';

void main() {
  group('wire enums', () {
    test('decode known values', () {
      expect(ChatRole.fromWire('assistant'), ChatRole.assistant);
      expect(SessionMode.fromWire('human'), SessionMode.human);
      expect(SessionStatus.fromWire('escalated'), SessionStatus.escalated);
    });

    test('never throw on new server-side values', () {
      expect(ChatRole.fromWire('moderator'), ChatRole.unknown);
      expect(SessionMode.fromWire(''), SessionMode.unknown);
      expect(SessionStatus.fromWire('archived'), SessionStatus.unknown);
    });
  });

  group('ChatMessage.fromJson', () {
    test('parses a full server message and normalizes to UTC', () {
      final m = ChatMessage.fromJson({
        'id': 'm1',
        'sessionId': 's1',
        'role': 'assistant',
        'content': 'hello',
        'createdAt': '2026-07-03T10:00:00+08:00',
      });
      expect(m.id, 'm1');
      expect(m.role, ChatRole.assistant);
      expect(m.createdAt, DateTime.utc(2026, 7, 3, 2));
      expect(m.status, MessageStatus.sent);
    });

    test('tolerates missing fields instead of throwing', () {
      final m = ChatMessage.fromJson(const {'role': 'user'});
      expect(m.id, '');
      expect(m.content, '');
      expect(m.role, ChatRole.user);
    });

    test('copyWith changes only what was asked', () {
      final m = ChatMessage.fromJson(const {'id': 'm1', 'role': 'user', 'content': 'a'});
      final done = m.copyWith(content: 'ab', status: MessageStatus.streaming);
      expect(done.content, 'ab');
      expect(done.status, MessageStatus.streaming);
      expect(done.id, m.id);
      expect(m.content, 'a', reason: 'original is immutable');
    });
  });

  test('ChatSession round-trips and copyWith preserves id', () {
    final s = ChatSession.fromJson(const {'id': 's1', 'mode': 'ai', 'status': 'open'});
    expect(s, const ChatSession(id: 's1', mode: SessionMode.ai, status: SessionStatus.open));
    final esc = s.copyWith(mode: SessionMode.human, status: SessionStatus.escalated);
    expect(esc.id, 's1');
    expect(esc.status, SessionStatus.escalated);
  });

  test('exceptions carry their designed recovery data', () {
    const rate = ChatRateLimitException('daily cap', retryAfter: Duration(minutes: 5));
    expect(rate.retryAfter, const Duration(minutes: 5));
    const stream = ChatStreamException('dropped', partialText: 'partial answer');
    expect(stream.partialText, 'partial answer');
    // sealed: every variant is a ChatException with a message
    const List<ChatException> all = [
      ChatNetworkException('offline'),
      ChatAuthException.missing(),
      ChatNotFoundException('gone'),
      rate,
      stream,
      ChatApiException(500, 'boom'),
    ];
    for (final e in all) {
      expect(e.message, isNotEmpty);
    }
  });
}
