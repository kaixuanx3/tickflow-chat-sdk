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

const session = ChatSession(id: 's1', mode: SessionMode.ai, status: SessionStatus.open);

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

  test('a full turn: echo → tokens stream in → done settles everything', () async {
    await engine.send('hi');
    await emit(const TokenDelta('He'));

    expect(engine.state.isStreaming, isTrue);
    expect(engine.state.messages[0].status, MessageStatus.sent,
        reason: 'first token confirms the echo');
    expect(engine.state.messages[1].status, MessageStatus.streaming);

    await emit(const TokenDelta('llo'));
    expect(engine.state.messages[1].content, 'Hello');

    await emit(const StreamDone(escalated: false));
    expect(engine.state.isStreaming, isFalse);
    expect(engine.state.messages[1].status, MessageStatus.sent);
    expect(engine.state.session.status, SessionStatus.open);
  });

  test('done with escalated:true flips the session status', () async {
    await engine.send('I was charged twice');
    await emit(const TokenDelta('Let me hand you over.'));
    await emit(const StreamDone(escalated: true));
    expect(engine.state.session.status, SessionStatus.escalated);
  });

  test('initiation failure marks the echo failed and surfaces a typed error', () async {
    transport.throwOnSend = const ChatRateLimitException('daily cap');
    await engine.send('hi');
    expect(engine.state.messages.single.status, MessageStatus.failed);
    expect(engine.state.error, isA<ChatRateLimitException>());
  });

  test('mid-stream failure keeps the partial reply and reports it', () async {
    await engine.send('hi');
    await emit(const TokenDelta('partial ans'));
    await emit(const StreamFailure('connection lost'));

    expect(engine.state.isStreaming, isFalse);
    expect(engine.state.messages[1].content, 'partial ans');
    expect(engine.state.messages[1].status, MessageStatus.failed);
    expect(engine.state.messages[0].status, MessageStatus.sent,
        reason: 'the echo reached the server; the reply is what failed');
    expect(
      engine.state.error,
      isA<ChatStreamException>().having((e) => e.partialText, 'partialText', 'partial ans'),
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
    expect(first.messages, hasLength(2), reason: 'late listener sees current state');
  });

  test('dispose closes the transport', () async {
    await engine.dispose();
    expect(transport.closed, isTrue);
  });
}
