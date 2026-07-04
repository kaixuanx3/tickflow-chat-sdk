/// Wire enums decode through [fromWire] with an `unknown` fallback so a new
/// server-side value never crashes an older client.
enum ChatRole {
  user,
  assistant,
  agent,
  system,
  unknown;

  static ChatRole fromWire(String s) => switch (s) {
    'user' => user,
    'assistant' => assistant,
    'agent' => agent,
    'system' => system,
    _ => unknown,
  };
}

enum SessionMode {
  ai,
  human,
  unknown;

  static SessionMode fromWire(String s) => switch (s) {
    'ai' => ai,
    'human' => human,
    _ => unknown,
  };
}

enum SessionStatus {
  open,
  escalated,
  closed,
  unknown;

  static SessionStatus fromWire(String s) => switch (s) {
    'open' => open,
    'escalated' => escalated,
    'closed' => closed,
    _ => unknown,
  };
}

/// Client-only send/stream lifecycle of a message; never serialized outbound.
enum MessageStatus { sending, streaming, sent, failed }
