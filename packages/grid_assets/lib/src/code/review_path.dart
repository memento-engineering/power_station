/// The ONE path vocabulary the review circuits classify a change with.
///
/// Two consumers read the same predicates: the docs committee
/// (`docs_committee.dart`), which routes a bead by its declared `## Touches`
/// and fences its lanes against foreign files, and the committee-selection
/// classifier (`committee_selection.dart`), which elects review lanes from the
/// pinned diff's changed paths. Owning the vocabulary in this neutral library
/// keeps the two from drifting apart: ratified A36's rule that [isMetadataPath]
/// is a strict SUPERSET of [isDocsPath] holds in exactly one place.
library;

import 'package:path/path.dart' as p;

/// Whether [path] is a DOCS path — any `.md` file anywhere, or any path with a
/// segment that is exactly `docs`.
bool isDocsPath(String path) {
  final normalized = p.posix.normalize(path.trim());
  if (normalized.isEmpty || normalized == '.') return false;
  if (normalized.toLowerCase().endsWith('.md')) return true;
  return p.posix.split(normalized).contains('docs');
}

/// The file extensions a METADATA path may carry — prose and configuration,
/// never source.
const Set<String> kMetadataPathExtensions = {
  '.md',
  '.yaml',
  '.yml',
  '.json',
  '.toml',
};

/// The extension-less file NAMES a metadata path may carry.
const Set<String> kMetadataPathFilenames = {'LICENSE'};

/// Whether [path] is a METADATA path — prose or configuration, never source.
///
/// A strict SUPERSET of [isDocsPath]: every docs path is metadata, plus any
/// file whose extension is in [kMetadataPathExtensions] (`CHANGELOG.md`,
/// `pubspec.yaml`, `example-config.json`, `Cargo.toml`) and any file whose
/// name is in [kMetadataPathFilenames] (`LICENSE`).
///
/// An ALLOW-list, never a deny-list of source extensions: a `.dart` / `.swift`
/// / `.kt` / `.go` / `.py` / `.js` / `.ts` file is not metadata because it is
/// not LISTED — and neither is an unlisted surface nobody thought of (a
/// `tool/release.sh`, a template, an extension-less script). That keeps the
/// fail-to-code posture: an unknown surface meets the CODE committee rather
/// than sneaking past a prose one.
bool isMetadataPath(String path) {
  if (isDocsPath(path)) return true;
  final normalized = p.posix.normalize(path.trim());
  if (normalized.isEmpty || normalized == '.') return false;
  final name = p.posix.basename(normalized);
  if (kMetadataPathFilenames.contains(name)) return true;
  final extension = p.posix.extension(name).toLowerCase();
  return extension.isNotEmpty && kMetadataPathExtensions.contains(extension);
}
