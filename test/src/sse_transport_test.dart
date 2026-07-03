import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tickflow_chat/src/transport/http_gateway.dart';
import 'package:tickflow_chat/src/transport/sse_transport.dart';
import 'package:tickflow_chat/tickflow_chat.dart';

const sseBody = 'data: {"delta":"Hi"}\n\nevent: done\ndata: {"done":true,"escalated":false}\n\n';

SseTransport transport(http.Client client) => SseTransport(
      gateway: HttpGateway(TickflowChatConfig(
        apiBaseUrl: Uri.parse('https://api.test'),
        tokenProvider: () async => 'jwt',
        httpClientFactory: () => client,
      )),
      sessionId: 's1',
    );

void main() {
  test('send pipes parsed events into the broadcast inbound stream', () async {
    final t = transport(MockClient.streaming((req, _) async =>
        http.StreamedResponse(Stream.value(utf8.encode(sseBody)), 200)));
    final collected = <ChatStreamEvent>[];
    final sub = t.inbound.listen(collected.add);

    await t.send('hello', clientTag: 'tag-1');
    await pumpEventQueue();

    expect((collected[0] as TokenDelta).delta, 'Hi');
    expect(collected[1], isA<StreamDone>());
    await sub.cancel();
    await t.close();
  });

  test('initiation failures throw from send, not inbound', () async {
    final t = transport(MockClient.streaming((req, _) async =>
        http.StreamedResponse(Stream.value(utf8.encode('{"error":"gone"}')), 404)));
    await expectLater(
      t.send('hello', clientTag: 'tag-1'),
      throwsA(isA<ChatNotFoundException>()),
    );
    await t.close();
  });

  test('a drop mid-reply surfaces as an inbound StreamFailure', () async {
    final controller = StreamController<List<int>>();
    final t = transport(MockClient.streaming(
        (req, _) async => http.StreamedResponse(controller.stream, 200)));
    final collected = <ChatStreamEvent>[];
    t.inbound.listen(collected.add);

    await t.send('hello', clientTag: 'tag-1');
    controller.add(utf8.encode('data: {"delta":"par"}\n\n'));
    await pumpEventQueue();
    controller.addError(http.ClientException('reset by peer'));
    await controller.close();
    await pumpEventQueue();

    expect((collected[0] as TokenDelta).delta, 'par');
    expect(collected[1], isA<StreamFailure>());
    await t.close();
  });

  test('cancelInFlight stops further events but keeps the transport usable', () async {
    final controller = StreamController<List<int>>();
    final t = transport(MockClient.streaming(
        (req, _) async => http.StreamedResponse(controller.stream, 200)));
    final collected = <ChatStreamEvent>[];
    t.inbound.listen(collected.add);

    await t.send('hello', clientTag: 'tag-1');
    controller.add(utf8.encode('data: {"delta":"a"}\n\n'));
    await pumpEventQueue();
    t.cancelInFlight();
    controller.add(utf8.encode('data: {"delta":"b"}\n\n'));
    await pumpEventQueue();

    expect(collected, hasLength(1));
    await t.close();
  });
}
