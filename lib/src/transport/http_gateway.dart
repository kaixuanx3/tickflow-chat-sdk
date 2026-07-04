import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/chat_config.dart';
import '../models/chat_exception.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/stream_event.dart';
import 'http_client_factory.dart';
import 'sse_parser.dart';

/// Internal 401 sentinel so [HttpGateway._authed] can retry exactly once.
class _Unauthorized implements Exception {
  const _Unauthorized();
}

/// The wire: REST calls, SSE bodies, Bearer auth. Everything it throws is a
/// [ChatException]; the raw token lives only on the stack for one call.
class HttpGateway {
  HttpGateway(this._config)
    : _client = (_config.httpClientFactory ?? createPlatformHttpClient)();

  final TickflowChatConfig _config;
  final http.Client _client;

  Future<ChatSession> createSession() => _authed((jwt) async {
    final res = await _guardNetwork(
      () => _client
          .post(
            _config.apiBaseUrl.resolve('/chat/sessions'),
            headers: _headers(jwt),
            // The JSON Content-Type header makes the server reject a truly
            // empty body (400); send an empty object for these bodyless POSTs.
            body: '{}',
          )
          .timeout(_config.requestTimeout),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throwForResponse(res.statusCode, res.body, res.headers);
    }
    return ChatSession.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  });

  /// Loads a session's persisted messages, oldest-first, from
  /// `{"messages": [...]}`. A 404 (not found, or not owned — the lookup is
  /// scoped server-side) surfaces as [ChatNotFoundException].
  Future<List<ChatMessage>> fetchHistory(String sessionId) =>
      _authed((jwt) async {
        final res = await _guardNetwork(
          () => _client
              .get(
                _config.apiBaseUrl.resolve(
                  '/chat/sessions/${Uri.encodeComponent(sessionId)}/messages',
                ),
                headers: _headers(jwt),
              )
              .timeout(_config.requestTimeout),
        );
        if (res.statusCode != 200) {
          _throwForResponse(res.statusCode, res.body, res.headers);
        }
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final messages = json['messages'] as List<dynamic>? ?? const [];
        return messages
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList(growable: false);
      });

  /// Escalates a session to human support via POST /escalate. Idempotent
  /// server-side (escalating an already-escalated session returns its current
  /// state). Returns the updated session; a 404 surfaces as
  /// [ChatNotFoundException].
  Future<ChatSession> escalate(String sessionId) => _authed((jwt) async {
    final res = await _guardNetwork(
      () => _client
          .post(
            _config.apiBaseUrl.resolve(
              '/chat/sessions/${Uri.encodeComponent(sessionId)}/escalate',
            ),
            headers: _headers(jwt),
            body: '{}', // bodyless POST — see createSession
          )
          .timeout(_config.requestTimeout),
    );
    if (res.statusCode != 200) {
      _throwForResponse(res.statusCode, res.body, res.headers);
    }
    return ChatSession.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  });

  /// Opens one AI reply turn: POST → `text/event-stream` → parsed events.
  ///
  /// Non-200 is mapped and thrown before any event; a 401 at open retries
  /// once through [_authed] (the request body has not been consumed yet).
  Future<Stream<ChatStreamEvent>> openMessageStream({
    required String sessionId,
    required String text,
    required String clientTag,
  }) => _authed((jwt) async {
    final req =
        http.Request('POST', _config.apiBaseUrl.resolve('/chat/messages'))
          ..headers.addAll(_headers(jwt))
          ..headers['Accept'] = 'text/event-stream'
          ..body = jsonEncode({
            'sessionId': sessionId,
            'text': text,
            'clientTag': clientTag,
          });
    final res = await _guardNetwork(
      () => _client.send(req).timeout(_config.requestTimeout),
    );
    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString();
      _throwForResponse(res.statusCode, body, res.headers);
    }
    return parseSseBytes(res.stream);
  });

  void dispose() => _client.close();

  Map<String, String> _headers(String jwt) => {
    'Authorization': 'Bearer $jwt',
    'Content-Type': 'application/json',
  };

  /// Token per request; on 401 ask the provider once more (the host may have
  /// re-logged-in) and retry. Still unauthorized → [ChatAuthException] for
  /// the host to route to login. Tickflow has no refresh tokens, so a second
  /// identical token fails fast without a wasted call.
  Future<T> _authed<T>(Future<T> Function(String jwt) run) async {
    try {
      final jwt = await _config.tokenProvider();
      if (jwt == null || jwt.isEmpty) throw const ChatAuthException.missing();
      try {
        return await run(jwt);
      } on _Unauthorized {
        final fresh = await _config.tokenProvider();
        if (fresh == null || fresh.isEmpty || fresh == jwt) {
          throw const ChatAuthException.expired();
        }
        try {
          return await run(fresh);
        } on _Unauthorized {
          throw const ChatAuthException.expired();
        }
      }
    } on ChatAuthException {
      // Single choke point: any terminal auth failure (missing or rejected
      // twice) notifies the host to route to login, then still surfaces.
      _config.onAuthFailure?.call();
      rethrow;
    }
  }

  Future<T> _guardNetwork<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on http.ClientException catch (e) {
      throw ChatNetworkException(e.message);
    } on TimeoutException {
      throw const ChatNetworkException('request timed out');
    }
  }

  Never _throwForResponse(
    int status,
    String body,
    Map<String, String> headers,
  ) {
    // Backend errors are always `{error: string}`; anything else degrades to
    // a generic message rather than leaking a raw body into the UI.
    String message() {
      try {
        final json = jsonDecode(body);
        if (json is Map<String, dynamic> && json['error'] is String) {
          return json['error'] as String;
        }
      } on FormatException {
        // fall through
      }
      return 'request failed ($status)';
    }

    switch (status) {
      case 401:
        throw const _Unauthorized();
      case 404:
        throw ChatNotFoundException(message());
      case 429:
        final seconds = int.tryParse(headers['retry-after'] ?? '');
        throw ChatRateLimitException(
          message(),
          retryAfter: seconds == null ? null : Duration(seconds: seconds),
        );
      default:
        throw ChatApiException(status, message());
    }
  }
}
