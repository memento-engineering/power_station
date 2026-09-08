/// The pack's own runner — the transport that makes the vended [DartCommand]
/// reachable as `dart run dart_grid_assets:dart_grid_assets <verb>` from any
/// checkout that resolves this package (a workspace root's Melos script, say).
///
/// LOGIC-FREE by rule: it assembles the exported Command and renders nothing
/// of its own. A composing station adds the same Command to its own runner.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_grid_assets/dart_grid_assets.dart';

/// Runs the DART domain's exported Command over [arguments].
Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<int>(
    'dart_grid_assets',
    'The DART domain grid assets — the vended `dart` domain Command '
        '(pub dev-time linkage and the release ops).',
  )..addCommand(DartCommand());
  try {
    exitCode = await runner.run(arguments) ?? 0;
  } on UsageException catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  }
}
