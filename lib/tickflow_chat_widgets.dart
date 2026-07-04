/// Default Material chat UI for the Tickflow chat SDK.
///
/// Phase 0 ships a barebones [ChatView] proving the pipeline end-to-end;
/// theming, localization and slot builders arrive in Phase 4. Consumers
/// with their own UI import the core or riverpod barrels and skip this one.
library;

export 'src/widgets/chat_view.dart';
export 'src/widgets/tickflow_chat_localizations.dart';
export 'src/widgets/tickflow_chat_theme.dart';
