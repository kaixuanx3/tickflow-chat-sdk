import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tickflow_chat/tickflow_chat.dart';

class FakeTransport implements ChatTransport {
  final controller = StreamController<ChatStreamEvent>.broadcast();
  final sent = <(String, String)>[]; // (text, clientTag)
  Exception? throwOnSend;
  var cancelled = 0;
  var closed = false;

  @override
  Stream<ChatStreamEvent> get inbound => controller.stream;

  @override
  Future<void> open() async {}

  @override
  Future<void> send(String text, {required String clientTag}) async {
    if (throwOnSend != null) throw throwOnSend!;
    sent.add((text, clientTag));
  }

  @override
  void cancelInFlight() => cancelled++;

  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }
}

const session = ChatSession(
  id: 's1',
  mode: SessionMode.ai,
  status: SessionStatus.open,
);

void main() {
  late FakeTransport transport;
  late ChatSessionEngine engine;

  setUp(() {
    transport = FakeTransport();
    engine = ChatSessionEngine(session: session, transport: transport);
  });

  tearDown(() => engine.dispose());

  Future<void> emit(ChatStreamEvent e) async {
    transport.controller.add(e);
    await pumpEventQueue();
  }

  test('send appends an optimistic echo before any network result', () async {
    await engine.send('  hello  ');
    final last = engine.state.messages.single;
    expect(last.role, ChatRole.user);
    expect(last.content, 'hello', reason: 'trimmed');
    expect(last.status, MessageStatus.sending);
    expect(last.clientTag, transport.sent.single.$2);
  });

  test(
    'a full turn: echo → tokens stream in → done settles everything',
    () async {
      await engine.send('hi');
      await emit(const TokenDelta('He'));

      expect(engine.state.isStreaming, isTrue);
      expect(
        engine.state.messages[0].status,
        MessageStatus.sent,
        reason: 'first token confirms the echo',
      );
      expect(engine.state.messages[1].status, MessageStatus.streaming);

      await emit(const TokenDelta('llo'));
      expect(engine.state.messages[1].content, 'Hello');

      await emit(const StreamDone(escalated: false));
      expect(engine.state.isStreaming, isFalse);
      expect(engine.state.messages[1].status, MessageStatus.sent);
      expect(engine.state.session.status, SessionStatus.open);
    },
  );

  test('done with escalated:true flips the session status', () async {
    await engine.send('I was charged twice');
    await emit(const TokenDelta('Let me hand you over.'));
    await emit(const StreamDone(escalated: true));
    expect(engine.state.session.status, SessionStatus.escalated);
  });

  test(
    'initiation failure marks the echo failed and surfaces a typed error',
    () async {
      transport.throwOnSend = const ChatRateLimitException('daily cap');
      await engine.send('hi');
      expect(engine.state.messages.single.status, MessageStatus.failed);
      expect(engine.state.error, isA<ChatRateLimitException>());
    },
  );

  test('mid-stream failure keeps the partial reply and reports it', () async {
    await engine.send('hi');
    await emit(const TokenDelta('partial ans'));
    await emit(const StreamFailure('connection lost'));

    expect(engine.state.isStreaming, isFalse);
    expect(engine.state.messages[1].content, 'partial ans');
    expect(engine.state.messages[1].status, MessageStatus.failed);
    expect(
      engine.state.messages[0].status,
      MessageStatus.sent,
      reason: 'the echo reached the server; the reply is what failed',
    );
    expect(
      engine.state.error,
      isA<ChatStreamException>().having(
        (e) => e.partialText,
        'partialText',
        'partial ans',
      ),
    );
  });

  test('failure before any token marks the echo failed for retry', () async {
    await engine.send('hi');
    await emit(const StreamFailure('reset'));
    expect(engine.state.messages.single.status, MessageStatus.failed);
  });

  test('send is a no-op while a reply is streaming', () async {
    await engine.send('first');
    await emit(const TokenDelta('a'));
    await engine.send('second');
    expect(transport.sent, hasLength(1));
    expect(engine.state.messages, hasLength(2));
  });

  test('a new send clears the previous error', () async {
    transport.throwOnSend = const ChatNetworkException('offline');
    await engine.send('hi');
    expect(engine.state.error, isNotNull);

    transport.throwOnSend = null;
    await engine.send('again');
    expect(engine.state.error, isNull);
  });

  test('cancelInFlight keeps the partial as sent', () async {
    await engine.send('hi');
    await emit(const TokenDelta('par'));
    engine.cancelInFlight();

    expect(transport.cancelled, 1);
    expect(engine.state.isStreaming, isFalse);
    expect(engine.state.messages[1].content, 'par');
    expect(engine.state.messages[1].status, MessageStatus.sent);
  });

  test('changes replays the current snapshot to a late subscriber', () async {
    await engine.send('hi');
    await emit(const TokenDelta('a'));
    final first = await engine.changes.first;
    expect(
      first.messages,
      hasLength(2),
      reason: 'late listener sees current state',
    );
  });

  test('dispose closes the transport', () async {
    await engine.dispose();
    expect(transport.closed, isTrue);
  });

  ChatMessage hist(String id, ChatRole role, String content) => ChatMessage(
    id: id,
    sessionId: session.id,
    role: role,
    content: content,
    createdAt: DateTime.utc(2026, 7, 1),
  );

  test(
    'load hydrates history and toggles isLoading around the fetch',
    () async {
      final gate = Completer<List<ChatMessage>>();
      final loading = engine.load(() => gate.future);
      expect(
        engine.state.isLoading,
        isTrue,
        reason: 'loading starts synchronously',
      );
      expect(engine.state.messages, isEmpty);

      gate.complete([
        hist('m1', ChatRole.user, 'earlier question'),
        hist('m2', ChatRole.assistant, 'earlier answer'),
      ]);
      await loading;

      expect(engine.state.isLoading, isFalse);
      expect(engine.state.messages, hasLength(2));
      expect(engine.state.messages[1].content, 'earlier answer');
    },
  );

  test('load failure surfaces as error and clears loading', () async {
    await engine.load(() async => throw const ChatNotFoundException('gone'));
    expect(engine.state.isLoading, isFalse);
    expect(engine.state.messages, isEmpty);
    expect(engine.state.error, isA<ChatNotFoundException>());
  });

  test('load maps an unexpected error type onto state.error', () async {
    await engine.load(() async => throw const FormatException('bad body'));
    expect(engine.state.isLoading, isFalse);
    expect(engine.state.error, isA<ChatApiException>());
  });

  test('history arriving after a send began does not wipe the echo', () async {
    final gate = Completer<List<ChatMessage>>();
    final loading = engine.load(() => gate.future);
    await engine.send('hi');
    gate.complete([hist('m1', ChatRole.user, 'old question')]);
    await loading;

    expect(engine.state.isLoading, isFalse);
    expect(
      engine.state.messages.single.content,
      'hi',
      reason: 'stale history must not replace the in-flight turn',
    );
  });

  test(
    'retry re-sends a failed message under its original clientTag',
    () async {
      transport.throwOnSend = const ChatNetworkException('offline');
      await engine.send('hello');
      final tag = engine.state.messages.single.clientTag!;
      expect(engine.state.messages.single.status, MessageStatus.failed);

      transport.throwOnSend = null;
      await engine.retry(tag);

      expect(
        transport.sent.single,
        ('hello', tag),
        reason: 'retry re-sends the same text under the original key',
      );
      expect(engine.state.messages.single.status, MessageStatus.sending);
      expect(engine.state.error, isNull);
    },
  );

  test('a successful retry streams and settles the reply', () async {
    transport.throwOnSend = const ChatNetworkException('offline');
    await engine.send('hi');
    final tag = engine.state.messages.single.clientTag!;

    transport.throwOnSend = null;
    await engine.retry(tag);
    await emit(const TokenDelta('Hello'));
    await emit(const StreamDone(escalated: false));

    expect(engine.state.messages[0].status, MessageStatus.sent);
    expect(engine.state.messages[1].content, 'Hello');
    expect(engine.state.messages[1].status, MessageStatus.sent);
  });

  test(
    'retry ignores an unknown tag and a settled (non-failed) message',
    () async {
      await engine.retry('nope');
      expect(transport.sent, isEmpty);

      await engine.send('hi');
      await emit(const TokenDelta('a'));
      await emit(const StreamDone(escalated: false));
      final tag = engine.state.messages[0].clientTag!;
      transport.sent.clear();
      await engine.retry(tag); // status is sent → no-op
      expect(transport.sent, isEmpty);
    },
  );

  test('a 429 records an absolute retryAt for the composer cooldown', () async {
    final before = DateTime.now().toUtc();
    transport.throwOnSend = const ChatRateLimitException(
      'daily cap',
      retryAfter: Duration(seconds: 30),
    );
    await engine.send('hi');

    expect(engine.state.error, isA<ChatRateLimitException>());
    final retryAt = engine.state.retryAt;
    expect(retryAt, isNotNull);
    expect(retryAt!.isAfter(before.add(const Duration(seconds: 29))), isTrue);
    expect(retryAt.isBefore(before.add(const Duration(seconds: 32))), isTrue);
  });

  test('a 429 without a Retry-After leaves retryAt null', () async {
    transport.throwOnSend = const ChatRateLimitException('cap');
    await engine.send('hi');
    expect(engine.state.error, isA<ChatRateLimitException>());
    expect(engine.state.retryAt, isNull);
  });

  test('the next send clears the rate-limit cooldown', () async {
    transport.throwOnSend = const ChatRateLimitException(
      'cap',
      retryAfter: Duration(seconds: 30),
    );
    await engine.send('hi');
    expect(engine.state.retryAt, isNotNull);

    transport.throwOnSend = null;
    await engine.send('again');
    expect(engine.state.retryAt, isNull);
  });

  test('escalate flips the session to the server-returned state', () async {
    const escalated = ChatSession(
      id: 's1',
      mode: SessionMode.ai,
      status: SessionStatus.escalated,
    );
    final e = ChatSessionEngine(
      session: session,
      transport: FakeTransport(),
      escalate: () async => escalated,
    );
    addTearDown(e.dispose);
    await e.escalate();
    expect(e.state.session.status, SessionStatus.escalated);
  });

  test(
    'a failed escalate surfaces on state.error, session unchanged',
    () async {
      final e = ChatSessionEngine(
        session: session,
        transport: FakeTransport(),
        escalate: () async => throw const ChatNotFoundException('gone'),
      );
      addTearDown(e.dispose);
      await e.escalate();
      expect(e.state.session.status, SessionStatus.open);
      expect(e.state.error, isA<ChatNotFoundException>());
    },
  );

  test('escalate is a no-op when the engine has no escalate wired', () async {
    await engine.escalate(); // setUp engine has no escalate callback
    expect(engine.state.session.status, SessionStatus.open);
    expect(engine.state.error, isNull);
  });

  test('awaiting-reply spans send until the first token', () async {
    await engine.send('hi');
    expect(engine.state.isAwaitingReply, isTrue);
    await emit(const TokenDelta('a'));
    expect(engine.state.isAwaitingReply, isFalse);
    expect(engine.state.isStreaming, isTrue);
  });

  test('awaiting-reply clears on failure and on a tokenless done', () async {
    await engine.send('hi');
    await emit(const StreamFailure('reset'));
    expect(engine.state.isAwaitingReply, isFalse);

    await engine.retry(engine.state.messages.single.clientTag!);
    expect(engine.state.isAwaitingReply, isTrue);
    await emit(const StreamDone(escalated: false));
    expect(engine.state.isAwaitingReply, isFalse);
  });

  test('awaiting-reply clears when the dispatch itself fails', () async {
    transport.throwOnSend = const ChatNetworkException('offline');
    await engine.send('hi');
    expect(engine.state.isAwaitingReply, isFalse);
  });
}
