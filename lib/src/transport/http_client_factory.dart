import 'package:http/http.dart' as http;

import 'http_client_factory_io.dart'
    if (dart.library.js_interop) 'http_client_factory_web.dart' as impl;

/// Platform-appropriate HTTP client for REST + SSE.
///
/// On web this must be the fetch-backed client: the default `BrowserClient`
/// buffers the whole response body, which silently defeats incremental SSE
/// on the app's primary platform. Overridable via
/// `TickflowChatConfig.httpClientFactory` (tests inject `MockClient`).
http.Client createPlatformHttpClient() => impl.createHttpClient();
