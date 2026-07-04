import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Returns the current Tickflow JWT, or null when signed out.
///
/// Called before every request — the host's secure-storage read (and any
/// future refresh) stays in the host. The SDK never stores the token.
typedef TokenProvider = Future<String?> Function();

@immutable
class TickflowChatConfig {
  const TickflowChatConfig({
    required this.apiBaseUrl,
    required this.tokenProvider,
    this.requestTimeout = const Duration(seconds: 30),
    this.httpClientFactory,
    this.onAuthFailure,
  });

  /// Backend origin, e.g. `Uri.parse('https://api.tickflow.app')`.
  final Uri apiBaseUrl;

  final TokenProvider tokenProvider;

  /// Applies to non-streaming REST calls and to *opening* an SSE stream,
  /// never to the lifetime of the stream itself.
  final Duration requestTimeout;

  /// Test seam / platform override. Defaults to a platform-appropriate
  /// client (a streaming fetch-based client on web).
  final http.Client Function()? httpClientFactory;

  /// Invoked once when a request terminally fails authentication — no token,
  /// or the backend rejected the token twice (Tickflow has no refresh). The
  /// host routes to login here (e.g. fires its session-expired provider). The
  /// same `ChatAuthException` also surfaces on the session state's error.
  final void Function()? onAuthFailure;
}
