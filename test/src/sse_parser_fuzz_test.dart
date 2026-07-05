import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tickflow_chat/src/transport/sse_parser.dart';
import 'package:tickflow_chat/tickflow_chat.dart';

/// Randomized-but-reproducible torture tests for the SSE pipeline (P5).
/// Every iteration derives from a fixed seed, so a failure names the exact
/// byte sequence to replay.

const _deltaPool = [
  'Hi',
  '你好，世界',
  'ok!',
  '📈 up 3%',
  'quote " and \\ slash',
  'a\tb',
  ' trailing ',
  'émoji Ω ≠ ascii',
];

/// Splits [bytes] into random 1–8 byte chunks.
List<List<int>> _randomChunks(Random rng, List<int> bytes) {
  final chunks = <List<int>>[];
  var i = 0;
  while (i < bytes.length) {
    final end = min(bytes.length, i + 1 + rng.nextInt(8));
    chunks.add(bytes.sublist(i, end));
    i = end;
  }
  return chunks;
}

/// A valid wire stream: heartbeats sprinkled between delta frames, LF or
/// CRLF line endings, closed by a done frame. Returns (bytes, deltas).
(List<int>, List<String>) _validStream(Random rng) {
  final eol = rng.nextBool() ? '\n' : '\r\n';
  final deltas = List.generate(
    1 + rng.nextInt(6),
    (_) => _deltaPool[rng.nextInt(_deltaPool.length)],
  );
  final buffer = StringBuffer();
  for (final delta in deltas) {
    if (rng.nextInt(3) == 0) buffer.write(': ping$eol$eol');
    buffer.write('data: ${jsonEncode({'delta': delta})}$eol$eol');
  }
  final escalated = rng.nextBool();
  buffer.write(
    'event: done${eol}data: {"done":true,"escalated":$escalated}$eol$eol',
  );
  return (utf8.encode(buffer.toString()), deltas);
}

void main() {
  test(
    'fuzz: valid streams survive arbitrary chunking byte-for-byte',
    () async {
      for (var seed = 0; seed < 300; seed++) {
        final rng = Random(seed);
        final (bytes, deltas) = _validStream(rng);
        final events = await parseSseBytes(
          Stream.fromIterable(_randomChunks(rng, bytes)),
        ).toList();

        expect(
          events.whereType<TokenDelta>().map((e) => e.delta).toList(),
          deltas,
          reason: 'seed $seed',
        );
        expect(events.last, isA<StreamDone>(), reason: 'seed $seed');
        expect(
          events.whereType<StreamFailure>(),
          isEmpty,
          reason: 'seed $seed',
        );
      }
    },
  );

  test('fuzz: arbitrary garbage bytes never throw', () async {
    for (var seed = 0; seed < 300; seed++) {
      final rng = Random(1000 + seed);
      final garbage = List.generate(rng.nextInt(400), (_) => rng.nextInt(256));
      // Must complete without an error, whatever nonsense arrived — a
      // corrupt frame degrades to a StreamFailure event, never a throw.
      final events = await parseSseBytes(
        Stream.fromIterable(_randomChunks(rng, garbage)),
      ).toList();
      for (final event in events) {
        expect(event, isA<ChatStreamEvent>(), reason: 'seed $seed');
      }
    }
  });

  test(
    'fuzz: truncated streams yield a clean prefix and never throw',
    () async {
      for (var seed = 0; seed < 300; seed++) {
        final rng = Random(2000 + seed);
        final (bytes, deltas) = _validStream(rng);
        final cut = 1 + rng.nextInt(bytes.length);
        final events = await parseSseBytes(
          Stream.fromIterable(_randomChunks(rng, bytes.sublist(0, cut))),
        ).toList();

        final seen = events
            .whereType<TokenDelta>()
            .map((e) => e.delta)
            .toList();
        expect(
          seen,
          deltas.sublist(0, seen.length),
          reason: 'seed $seed: parsed deltas must be a prefix of the original',
        );
      }
    },
  );

  test(
    'fuzz: valid frames interleaved with corrupt ones keep flowing',
    () async {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(3000 + seed);
        final good = _deltaPool[rng.nextInt(_deltaPool.length)];
        final bytes = utf8.encode(
          'data: {not json${String.fromCharCode(rng.nextInt(128))}}\n\n'
          'data: ${jsonEncode({'delta': good})}\n\n'
          'event: done\ndata: {"done":true,"escalated":false}\n\n',
        );
        final events = await parseSseBytes(
          Stream.fromIterable(_randomChunks(rng, bytes)),
        ).toList();

        expect(events[0], isA<StreamFailure>(), reason: 'seed $seed');
        expect(
          (events[1] as TokenDelta).delta,
          good,
          reason: 'seed $seed: the bad frame must not eat the good one',
        );
        expect(events.last, isA<StreamDone>(), reason: 'seed $seed');
      }
    },
  );
}
