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

    // Whether this turn already produced a terminal event, so a clean close
    // that arrives after one doesn't double-fail it.
    var settled = false;
    void emit(ChatStreamEvent event) {
      if (event is StreamDone || event is StreamFailure) settled = true;
      if (!_inbound.isClosed) _inbound.add(event);
    }

    _active = events.listen(
      emit,
      // A drop mid-reply becomes a typed inbound event; the engine keeps the
      // partial text and offers retry instead of seeing a stream error.
      onError: (Object e) => emit(
        StreamFailure(e is ChatException ? e.message : 'connection lost'),
      ),
      // A clean close before the `done` frame (a truncated reply — server
      // crash, dropped socket, proxy cut) is still a failure: surface it so
      // the turn settles and offers retry instead of hanging mid-stream.
      onDone: () {
        if (!settled) {
          emit(
            const StreamFailure('connection closed before the reply finished'),
          );
        }
        _active = null;
      },
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
