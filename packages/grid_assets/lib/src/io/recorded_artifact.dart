/// The pack's ONE writer of a recorded artifact.
///
/// A *recorded artifact* is a file this package generates and then keeps under
/// version control as evidence: a measurement corpus's baseline, a generated
/// report. Two libraries own one each — `search/search_recall.dart` records the
/// semantic-recall baseline, `code/spec_contract_shadow.dart` records the spec
/// record-grammar shadow report — and both regenerate through a thin `tool/`
/// CLI that is read-only unless given an explicit record flag.
///
/// What those two share is not their corpus, their measurement, or what their
/// record flag MEANS; each of those is genuinely different and each library
/// says so. What they share is this: a recorded artifact is compared against
/// its regeneration by a test, so a half-written one turns a crash mid-write
/// into a confusing diff rather than a clean rerun. [recordArtifact] is the
/// single owner of the temp-file-plus-rename discipline that prevents it, and
/// `spec_contract_shadow_test.dart` fences that ownership by refusing a second
/// rename site anywhere in `lib/`.
library;

import 'dart:io';

/// Writes [contents] to [file], creating parents, so no reader observes a
/// partially written artifact.
///
/// The write lands in a `.tmp` sibling and is then renamed over [file].
/// Renaming within a directory is atomic on the platforms this pack runs on,
/// so [file] only ever holds a complete artifact: a crash mid-write leaves the
/// previous recorded artifact intact and a stray `.tmp` beside it, which the
/// next record run overwrites.
Future<void> recordArtifact(File file, String contents) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(contents);
  await temporary.rename(file.path);
}
