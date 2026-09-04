import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:grid_assets/grid_assets.dart';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addFlag(
      'check',
      negatable: false,
      help: 'Verify both generated outputs are current; write nothing.',
    );
  final options = parser.parse(arguments);
  try {
    io.exitCode = runGridAssetsGenerator(
      packageRoot: io.Directory.current.path,
      check: options.flag('check'),
    );
  } on GridBlockException catch (error) {
    io.stderr.writeln(error.message);
    io.exitCode = 2;
  }
}
