import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tickflow_chat/src/transport/sse_parser.dart';
import 'package:tickflow_chat/tickflow_chat.dart';

/// Streams [bytes] split at [cut] — the adversarial two-chunk read.
Stream<List<int>> splitAt(List<int> bytes, int cut) async* {
  yield bytes.sublist(0, cut);
  yield bytes.sublist(cut);
}

Future<List<ChatStreamEvent>> parse(Stream<List<int>> bytes) =>
    parseSseBytes(bytes).toList();

void main() {
  const canonical =
      'data: {"delta":"He"}\n\n'
      'data: {"delta":"llo 世界"}\n\n'
      'event: done\ndata: {"done":true,"escalated":false}\n\n';

  void expectCanonical(List<ChatStreamEvent> events) {
    expect(events, hasLength(3));
    expect((events[0] as TokenDelta).delta, 'He');
    expect((events[1] as TokenDelta).delta, 'llo 世界');
    expect((events[2] as StreamDone).escalated, isFalse);
  }

  test('parses a canonical AI turn', () async {
    expectCanonical(await parse(Stream.value(utf8.encode(canonical))));
  });

  test(
    'is invariant under a split at every byte offset (multi-byte safe)',
    () async {
      final bytes = utf8.encode(canonical);
      for (var cut = 1; cut < bytes.length; cut++) {
        expectCanonical(await parse(splitAt(bytes, cut)));
      }
    },
  );

  test('handles CRLF line endings', () async {
    const crlf =
        'data: {"delta":"a"}\r\n\r\nevent: done\r\ndata: {"done":true,"escalated":true}\r\n\r\n';
    final events = await parse(Stream.value(utf8.encode(crlf)));
    expect((events[0] as TokenDelta).delta, 'a');
    expect((events[1] as StreamDone).escalated, isTrue);
  });

  test('ignores comment/heartbeat lines and empty frames', () async {
    const noisy = ': keep-alive\n\n: ping\ndata: {"delta":"x"}\n\n\n\n';
    final events = await parse(Stream.value(utf8.encode(noisy)));
    expect(events, hasLength(1));
    expect((events[0] as TokenDelta).delta, 'x');
  });

  test('joins multi-line data with newline before decoding', () async {
    // JSON split across two data lines is still one payload
    const multi = 'data: {"delta":\ndata: "ab"}\n\n';
    final events = await parse(Stream.value(utf8.encode(multi)));
    expect((events.single as TokenDelta).delta, 'ab');
  });

  test('strips exactly one leading space after the colon', () async {
    final framed = await Stream.value('data:  {"delta":"x"}')
        .transform(const LineSplitter())
        .transform(const SseEventFramer())
        .toList();
    // one space is field syntax, the second belongs to the value
    expect(framed, isEmpty, reason: 'no blank line yet — nothing dispatches');
    const withBlank = 'data:  {"delta":"x"}\n\n';
    final events = await parse(Stream.value(utf8.encode(withBlank)));
    expect((events.single as TokenDelta).delta, 'x');
  });

  test('malformed JSON becomes StreamFailure, never a throw', () async {
    const bad = 'data: {not json}\n\nevent: done\ndata: also-bad\n\n';
    final events = await parse(Stream.value(utf8.encode(bad)));
    expect(events, hasLength(2));
    expect(events[0], isA<StreamFailure>());
    expect(events[1], isA<StreamFailure>());
  });

  test('error frames surface their message', () async {
    const err = 'event: error\ndata: {"message":"provider unavailable"}\n\n';
    final events = await parse(Stream.value(utf8.encode(err)));
    expect((events.single as StreamFailure).message, 'provider unavailable');
  });

  test('done with escalated:true and no prior tokens', () async {
    const only = 'event: done\ndata: {"done":true,"escalated":true}\n\n';
    final events = await parse(Stream.value(utf8.encode(only)));
    expect((events.single as StreamDone).escalated, isTrue);
  });

  test(
    'discards an unterminated trailing frame (dropped connection)',
    () async {
      const dropped = 'data: {"delta":"a"}\n\ndata: {"delta":"never finis';
      final events = await parse(Stream.value(utf8.encode(dropped)));
      expect(events, hasLength(1));
      expect((events.single as TokenDelta).delta, 'a');
    },
  );

  test('empty deltas are suppressed as no-ops', () async {
    const empty = 'data: {"delta":""}\n\ndata: {"delta":"x"}\n\n';
    final events = await parse(Stream.value(utf8.encode(empty)));
    expect(events, hasLength(1));
  });
}
