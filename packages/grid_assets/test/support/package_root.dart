// The ONE package-root authority every source read in this suite resolves
// against — cwd-independent by construction.
//
// The working directory is a PROCESS property and `dart test` runs test files
// in concurrent isolates of one process, so a path built off it can be read
// while a sibling suite has that global pointed somewhere else: the read throws
// `PathNotFoundException`, or — worse — resolves a different tree and asserts
// against it. Which happens depends on isolate scheduling, not on the diff, so
// it never reproduces in isolation. Nothing in this tree assigns the working
// directory and nothing reads it; every package-local path is
// `p.join(packageRoot(), …)`.
//
// The anchor is this library's OWN location on disk, taken off a stack frame
// captured here: the one thing an isolate knows about itself that no other
// isolate can move.
//
// Deliberately NOT `Platform.script` — under `dart test` that is a throwaway
// kernel dill in the system temp dir, not a file in this package (it IS this
// file when the sibling probe executable runs, which is why the error below
// names it).
//
// Deliberately NOT `PackagedAssetLoader.root` either: `track_d_assets_test.dart`
// verifies that production resolution, so a locator built on the code under
// test could not tell a broken loader from a broken locator. This walk shares
// no mechanism with it — the loader resolves a `package:` URI through the
// package config, this reads a source location.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// This package's root: the directory whose `pubspec.yaml` is named
/// `grid_assets`.
///
/// The same absolute answer whatever the process cwd is, and whoever else is
/// moving it. Resolved once per isolate.
String packageRoot() => _packageRoot ??= _resolvePackageRoot();

String? _packageRoot;

/// Walks up from [_selfFile] to the enclosing `grid_assets` package.
///
/// Throws a [StateError] naming both the anchor and [Platform.script] when no
/// such package encloses this file: a locator that silently found nothing
/// would make every source fence built on it vacuous.
String _resolvePackageRoot() {
  final self = _selfFile();
  var dir = File(self).parent;
  while (!_isGridAssetsPackage(dir)) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'no pubspec.yaml naming grid_assets above $self '
        '(Platform.script: ${Platform.script})',
      );
    }
    dir = parent;
  }
  return dir.path;
}

/// Whether [dir] is the `grid_assets` package root — its own `pubspec.yaml`
/// declaring that name, never a parent workspace's or a sibling pack's.
bool _isGridAssetsPackage(Directory dir) {
  final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return false;
  return pubspec.readAsLinesSync().any(_declaresGridAssets.hasMatch);
}

final RegExp _declaresGridAssets = RegExp(r'^name:\s*grid_assets\s*$');

/// This library's own absolute path, read off the top frame of a trace
/// captured inside it.
///
/// Throws a [StateError] when that frame carries no `file:` URI: the anchor is
/// gone, and a guessed root is a silent wrong answer.
String _selfFile() {
  final frame = StackTrace.current.toString().split('\n').first;
  final match = _frameFileUri.firstMatch(frame);
  if (match == null) {
    throw StateError('no file: URI in the anchoring stack frame "$frame"');
  }
  return File.fromUri(Uri.parse(match.group(1)!)).absolute.path;
}

final RegExp _frameFileUri = RegExp(r'\((file:[^)]*\.dart):\d+:\d+\)');
