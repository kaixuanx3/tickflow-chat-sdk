import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import '../models/stream_event.dart';

/// One framed Server-Sent Event: an event name ('' = default) and its data
/// lines joined with `\n`.
@immutable
class SseEvent {
  const SseEvent({this.event = '', this.data = ''});
  final String event;
  final String data;

  @override
  bool operator ==(Object other) =>
      other is SseEvent && other.event == event && other.data == data;

  @override
  int get hashCode => Object.hash(event, data);

  @override
  String toString() => 'SseEvent($event, $data)';
}

/// Frames [LineSplitter] output into [SseEvent]s.
///
/// Owns only true SSE semantics — byte chunking is `utf8.decoder`'s job and
/// line boundaries are [LineSplitter]'s, so arbitrary network chunk splits
/// can't corrupt a frame:
/// - `field: value` with exactly one leading space stripped
/// - multi-line `data:` joined with `\n`
/// - comment/heartbeat lines (`:`) ignored
/// - blank line dispatches; empty frames are suppressed
/// - an unterminated trailing frame is discarded (per the SSE spec)
class SseEventFramer extends StreamTransformerBase<String, SseEvent> {
  const SseEventFramer();

  @override
  Stream<SseEvent> bind(Stream<String> lines) async* {
    var event = '';
    final data = <String>[];

    await for (final line in lines) {
      if (line.isEmpty) {
        if (event.isNotEmpty || data.isNotEmpty) {
          yield SseEvent(event: event, data: data.join('\n'));
        }
        event = '';
        data.clear();
        continue;
      }
      if (line.startsWith(':')) continue; // comment / proxy heartbeat

      final colon = line.indexOf(':');
      final field = colon == -1 ? line : line.substring(0, colon);
      var value = colon == -1 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);

      switch (field) {
        case 'data':
          data.add(value);
        case 'event':
          event = value;
        default:
          break; // id / retry / unknown fields are not part of the contract
      }
    }
  }
}

/// Maps one framed event onto the wire contract; returns null for no-ops.
///
/// Malformed JSON becomes a [StreamFailure] — never a throw — so one bad
/// frame degrades to a typed error instead of killing the stream pipeline.
ChatStreamEvent? chatStreamEventFrom(SseEvent e) {
  Map<String, dynamic>? decode() {
    try {
      final v = jsonDecode(e.data);
      return v is Map<String, dynamic> ? v : null;
    } on FormatException {
      return null;
    }
  }

  switch (e.event) {
    case 'done':
      final json = decode();
      if (json == null) return const StreamFailure('malformed done frame');
      return StreamDone(escalated: json['escalated'] == true);
    case 'error':
      final json = decode();
      return StreamFailure((json?['message'] as String?) ?? 'stream error');
    default:
      final json = decode();
      if (json == null) return const StreamFailure('malformed data frame');
      final delta = json['delta'] as String?;
      if (delta == null || delta.isEmpty) return null;
      return TokenDelta(delta);
  }
}

/// The full pipe from an SSE response body to chat events. Survives
/// arbitrary chunk boundaries: a UTF-8 code point, a line, or a frame split
/// across reads reassembles identically. Malformed UTF-8 decodes to
/// replacement characters instead of throwing — a corrupt byte degrades one
/// delta (or one frame, via the malformed-JSON path) rather than killing
/// the stream.
Stream<ChatStreamEvent> parseSseBytes(Stream<List<int>> bytes) => bytes
    .transform(const Utf8Decoder(allowMalformed: true))
    .transform(const LineSplitter())
    .transform(const SseEventFramer())
    .map(chatStreamEventFrom)
    .where((e) => e != null)
    .cast<ChatStreamEvent>();
