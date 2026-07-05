import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tickflow_chat/tickflow_chat.dart';

void main() {
  test('the wire-reported version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(.+)$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!.trim();
    expect(
      tickflowChatVersion,
      version,
      reason: 'bump lib/src/version.dart together with pubspec.yaml',
    );
  });
}
