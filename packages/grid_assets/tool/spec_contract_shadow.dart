import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:grid_assets/grid_assets.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()..addFlag('record', negatable: false);
  final options = parser.parse(arguments);
  io.exitCode = await runSpecContractShadow(
    root: io.Directory.current.path,
    record: options.flag('record'),
  );
}
