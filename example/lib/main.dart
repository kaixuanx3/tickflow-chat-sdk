import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tickflow_chat/tickflow_chat.dart';
import 'package:tickflow_chat/tickflow_chat_riverpod.dart';
import 'package:tickflow_chat/tickflow_chat_widgets.dart';

/// Minimal host wiring for the SDK: inbox → thread against a Tickflow
/// backend. Run with your backend URL and a JWT for an existing user:
///
/// ```sh
/// flutter run \
///   --dart-define=API_URL=http://localhost:3000 \
///   --dart-define=JWT=<token from POST /auth/login>
/// ```
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:3000',
);
const jwt = String.fromEnvironment('JWT');

void main() {
  runApp(
    ProviderScope(
      overrides: [
        // The one required override: where the backend is and how to get a
        // token. Real hosts read the token from secure storage and route to
        // login via onAuthFailure.
        chatConfigProvider.overrideWithValue(
          TickflowChatConfig(
            apiBaseUrl: Uri.parse(apiUrl),
            tokenProvider: () async => jwt.isEmpty ? null : jwt,
            onTelemetry: (event) => debugPrint('chat telemetry: $event'),
          ),
        ),
      ],
      child: const ExampleApp(),
    ),
  );
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tickflow_chat example',
      themeMode: ThemeMode.system,
      theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
      darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      localizationsDelegates: const [TickflowChatLocalizations.delegate],
      supportedLocales: TickflowChatLocalizations.supportedLocales,
      home: const InboxScreen(),
    );
  }
}

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ThreadScreen(sessionId: id)),
    );
    ref.invalidate(chatInboxProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: ChatInboxView(
        onOpenSession: (session) => _open(context, ref, session.id),
        onStartConversation: () async {
          final session = await ref.read(chatClientProvider).createSession();
          if (context.mounted) await _open(context, ref, session.id);
        },
      ),
    );
  }
}

class ThreadScreen extends StatelessWidget {
  const ThreadScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(TickflowChatLocalizations.of(context).assistantTitle),
        actions: [ChatEscalateButton(sessionId: sessionId)],
      ),
      body: ChatView(sessionId: sessionId),
    );
  }
}
