// The foreign-working-directory probe `track_d_assets_test.dart` launches.
//
// Constructs a [PackagedAssetLoader] with NO explicit root from a process whose
// working directory shares no ancestry with this checkout, so the loader's cwd
// walk-up fallback is guaranteed to miss and a successful load proves the
// package config resolved `extension/`. Loads every code-committee rubric, then
// prints the root it resolved so the parent can pin the exact directory.
//
// A child process rather than a `Directory.current` assignment: that property is
// process-global and `dart test` runs suites concurrently, so chdir'ing here to
// prove cwd-independence raced every sibling suite's source read.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';

void main() {
  final loader = PackagedAssetLoader();
  for (final rubricId in <String>[kGatingRubric, ...kLlmRubrics]) {
    final text = loader.loadRubric(rubricId);
    if (text.isEmpty || !text.contains(rubricId)) {
      stderr.writeln('rubric "$rubricId" did not load as itself');
      exitCode = 1;
      return;
    }
  }
  stdout.write(loader.root);
}
