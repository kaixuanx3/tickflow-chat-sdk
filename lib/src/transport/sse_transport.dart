import 'dart:async';

import '../models/chat_exception.dart';
import '../models/stream_event.dart';
import 'chat_transport.dart';
import 'http_gateway.dart';

/// AI mode: each [send] is one POST whose response body streams the reply.
class SseTransport implements ChatTransport {
  SseTransport({required HttpGateway gateway, required String sessionId})
    : _gateway = gateway,
      _sessionId = sessionId;

  final HttpGateway _gateway;
  final String _sessionId;
  final _inbound = StreamController<ChatStreamEvent>.broadcast();
  StreamSubscription<ChatStreamEvent>? _active;

  @override
  Stream<ChatStreamEvent> get inbound => _inbound.stream;

  @override
  Future<void> open() async {} // request-per-reply: nothing persistent

  @override
  Future<void> send(String text, {required String clientTag}) async {
    final events = await _gateway.openMessageStream(
      sessionId: _sessionId,
      text: text,
      clientTag: clientTag,
    );
    await _active?.cancel();
    _active = events.listen(
      _inbound.add,
      // A drop mid-reply becomes a typed inbound event; the engine keeps the
      // partial text and offers retry instead of seeing a stream error.
      onError: (Object e) => _inbound.add(
        StreamFailure(e is ChatException ? e.message : 'connection lost'),
      ),
      onDone: () => _active = null,
    );
  }

  @override
  void cancelInFlight() {
    // Cancelling the subscription closes the underlying HTTP connection, so
    // the reply stops costing tokens the moment the user leaves.
    _active?.cancel();
    _active = null;
  }

  @override
  Future<void> close() async {
    cancelInFlight();
    await _inbound.close();
  }
}
