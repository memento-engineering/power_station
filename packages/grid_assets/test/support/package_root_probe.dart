// The foreign-working-directory probe `package_root_test.dart` launches.
//
// It resolves [packageRoot] in its OWN process, started with a temp working
// directory, so the hazard that helper exists to remove is exercised for real
// and no test isolate ever writes the process-global cwd to do it. Reads this
// package's barrel THROUGH the resolved root before printing it, so a root that
// merely looks plausible cannot pass.
//
// Imports no `package:` URI of its own: what it proves is the helper's walk,
// not this executable's resolution.
import 'dart:io';

import 'package_root.dart';

void main() {
  final root = packageRoot();
  final barrel = File(
    [root, 'lib', 'grid_assets.dart'].join(Platform.pathSeparator),
  );
  if (!barrel.existsSync() || barrel.readAsStringSync().isEmpty) {
    stderr.writeln('unreadable barrel through $root');
    exitCode = 1;
    return;
  }
  stdout.write(root);
}
