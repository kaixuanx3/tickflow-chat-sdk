/// Pure-Dart core of the Tickflow chat SDK: configuration, models,
/// exceptions, transport seam and the session engine.
///
/// Riverpod bindings live in `tickflow_chat_riverpod.dart`; the default
/// Material widget lives in `tickflow_chat_widgets.dart`. This barrel must
/// stay importable without Flutter.
library;

export 'src/client/chat_client.dart';
export 'src/client/chat_read_marks.dart';
export 'src/config/chat_config.dart';
export 'src/engine/chat_session_engine.dart';
export 'src/engine/chat_session_state.dart';
export 'src/models/chat_exception.dart';
export 'src/models/chat_message.dart';
export 'src/models/chat_role.dart';
export 'src/models/chat_session.dart';
export 'src/models/chat_telemetry.dart';
export 'src/models/stream_event.dart';
export 'src/transport/chat_transport.dart';
export 'src/version.dart';
