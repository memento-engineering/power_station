/// Pub dev-time linkage — the DART domain's first payload (the
/// `SCRATCH-pub-capability-and-repo-split` design; typed CONFIGURATION, not
/// tools).
///
/// A work bead may declare "the desire to dev-time link" this work's checkout
/// to sibling package sources (e.g. `genesis_tree` → the local genesis
/// checkout). The substation already defines its location and the bead its own
/// worktree — those are projections; this config carries ONLY the linkage
/// intent, as data. Applying it is a PURE function: context → the
/// `pubspec_overrides.yaml` content (pub honors that file from the workspace
/// root at any checkout depth; melos 7 no longer owns it).
///
/// The contexts: [PubLinkContext.dev] (the root checkout — paths apply as
/// declared), [PubLinkContext.worktree] (a deep per-bead worktree at
/// `.grid/worktrees/<sub>/<bead>` — relative `../` paths break there, so
/// declared paths are ABSOLUTIZED against the station's dev root, fail-closed
/// when they can't be), and [PubLinkContext.stable] (git-pinned links emit
/// `git: {url, ref}` overrides — ADR-0003 D2; a link with no git pin resolves
/// from its own `pubspec.yaml` pin).
///
/// Hand-written immutable value types + JSON (the grid_assets payload style —
/// `DispatchCommand`/`LaunchSpec`; dependency-light, no codegen).
library;

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

/// Which resolution situation the linkage is being applied for.
enum PubLinkContext {
  /// The root checkout (local dev): declared paths apply as-is.
  dev,

  /// A deep per-bead worktree: declared paths are absolutized against the
  /// station's dev root (relative `../` paths do not resolve from
  /// `.grid/worktrees/<sub>/<bead>`).
  worktree,

  /// Stable: git-pinned links emit `git: {url, ref}` overrides (ADR-0003 D2);
  /// a link with no git pin resolves from its own `pubspec.yaml` pin (D5).
  stable;

  /// Parses a wire/flag [value]; null for an unknown one (fail-closed — the
  /// caller refuses rather than guessing a context).
  static PubLinkContext? parse(String? value) => switch (value) {
    'dev' => PubLinkContext.dev,
    'worktree' => PubLinkContext.worktree,
    'stable' => PubLinkContext.stable,
    _ => null,
  };
}

/// One package's declared linkage: the dev-time [devPath] source (the override
/// applied in dev/worktree contexts), the informational [hosted] pin, and the
/// [gitUrl]+[gitRef] git-tag pin the stable context emits as a `git:` override
/// (ADR-0003 D2).
@immutable
class PubLink {
  /// Creates the linkage declaration for [package].
  const PubLink({
    required this.package,
    this.devPath,
    this.hosted,
    this.gitUrl,
    this.gitRef,
  });

  /// The pub package name (e.g. `genesis_tree`).
  final String package;

  /// The dev-time path source — absolute, or relative to the station's dev
  /// root. Null ⇒ this link declares no dev-time override (stable pins stand).
  final String? devPath;

  /// The stable hosted constraint (informational — it lives in the pubspec
  /// proper; recorded here so the intent is complete/auditable).
  final String? hosted;

  /// The stable git url — applied in [PubLinkContext.stable] as a
  /// `git: {url, ref}` override (ADR-0003 D2). Pairs with [gitRef]: both, or
  /// the stable emitter refuses LOUDLY.
  final String? gitUrl;

  /// The stable git ref (the git tag pinned in [PubLinkContext.stable]). Pairs
  /// with [gitUrl]: both, or the stable emitter refuses LOUDLY.
  final String? gitRef;

  /// JSON form (the envelope payload wire).
  Map<String, Object?> toJson() => {
    'package': package,
    if (devPath != null) 'dev_path': devPath,
    if (hosted != null) 'hosted': hosted,
    if (gitUrl != null) 'git_url': gitUrl,
    if (gitRef != null) 'git_ref': gitRef,
  };

  /// The valid pub package-name shape (identifier chars only). Enforced at
  /// decode so a YAML-dangerous "name" (colons, spaces, hashes) can never reach
  /// the overrides emitter — the envelope is malformed instead (fail-closed).
  static final RegExp _validPackage = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// Parses [json]; throws [FormatException] on a missing/invalid package name
  /// (the envelope decoder maps that to a malformed result — fail-closed).
  static PubLink fromJson(Map<String, Object?> json) {
    final package = json['package'];
    if (package is! String || !_validPackage.hasMatch(package)) {
      throw const FormatException(
        'PubLink requires a valid pub package name '
        '(identifier characters only)',
      );
    }
    return PubLink(
      package: package,
      devPath: json['dev_path'] as String?,
      hosted: json['hosted'] as String?,
      gitUrl: json['git_url'] as String?,
      gitRef: json['git_ref'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PubLink &&
      other.package == package &&
      other.devPath == devPath &&
      other.hosted == hosted &&
      other.gitUrl == gitUrl &&
      other.gitRef == gitRef;

  @override
  int get hashCode => Object.hash(package, devPath, hosted, gitUrl, gitRef);
}

/// The `pub` slice of the DART domain payload: the declared [links].
@immutable
class PubLinkConfig {
  /// Creates the pub linkage config.
  const PubLinkConfig({this.links = const []});

  /// The declared per-package links.
  final List<PubLink> links;

  /// Whether any link declares a dev-time path (i.e. applying in a dev/worktree
  /// context would emit overrides).
  bool get hasDevLinks => links.any((l) => l.devPath != null);

  /// JSON form.
  Map<String, Object?> toJson() => {
    'links': [for (final l in links) l.toJson()],
  };

  /// Parses [json] (a missing/empty `links` is a valid empty config). A
  /// non-list `links` or a non-object entry throws [FormatException] —
  /// explicit, so the fail-closed path never rides an implicit cast error.
  static PubLinkConfig fromJson(Map<String, Object?> json) {
    final raw = json['links'];
    if (raw == null) return const PubLinkConfig();
    if (raw is! List) {
      throw const FormatException('"links" must be a list');
    }
    return PubLinkConfig(
      links: [
        for (final entry in raw)
          if (entry is Map)
            PubLink.fromJson(entry.cast<String, Object?>())
          else
            throw const FormatException('"links" entries must be objects'),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PubLinkConfig &&
      other.links.length == links.length &&
      () {
        for (var i = 0; i < links.length; i++) {
          if (other.links[i] != links[i]) return false;
        }
        return true;
      }();

  @override
  int get hashCode => Object.hashAll(links);
}

/// Derives the `pubspec_overrides.yaml` CONTENT for [config] under [context] —
/// the pure heart of the domain (no I/O; deterministic: links sorted by
/// package). Exhaustive over [PubLinkContext]:
///
/// - [PubLinkContext.dev] → path overrides exactly as declared (a relative
///   path resolves naturally from the root checkout).
/// - [PubLinkContext.worktree] → path overrides ABSOLUTIZED: an absolute
///   declaration passes through; a relative one is resolved against [devRoot]
///   (normalized). A relative declaration with NO [devRoot] — or a [devRoot]
///   that is itself relative (which would silently yield a still-relative,
///   broken override) — throws [StateError]: fail-closed, never a silently
///   broken override.
/// - [PubLinkContext.stable] → a `git: {url, ref, path: packages/<pkg>}`
///   override per git-pinned link (ADR-0003 D2). A link with a PARTIAL git pin
///   (one of [PubLink.gitUrl]/[PubLink.gitRef] but not both) is a LOUD
///   [StateError] refusal — never a silent path fallback (D2). A link with NO
///   git pin contributes nothing (its `pubspec.yaml` hosted/git pin stands —
///   ADR-0003 D5); no git-pinned links → null (the caller removes a stale
///   generated file).
///
/// Values are emitted as single-quoted YAML scalars (embedded quotes doubled),
/// so a value carrying YAML-hostile characters (`: `, ` #`, leading/trailing
/// spaces) can never corrupt the file. Package names are identifier-validated
/// at decode, so they need no quoting.
///
/// In dev/worktree, links with no [PubLink.devPath] contribute nothing; no dev
/// links at all → null (nothing to override).
String? pubspecOverridesFor(
  PubLinkConfig config,
  PubLinkContext context, {
  String? devRoot,
}) => switch (context) {
  PubLinkContext.dev || PubLinkContext.worktree => _pathOverridesFor(
    config,
    context,
    devRoot: devRoot,
  ),
  PubLinkContext.stable => _gitOverridesFor(config),
};

/// The dev/worktree path-override emission — UNCHANGED behavior from before the
/// stable-git work (ADR-0003 D5 keeps the co-development escape hatch:
/// dev/worktree still emit path overrides).
String? _pathOverridesFor(
  PubLinkConfig config,
  PubLinkContext context, {
  String? devRoot,
}) {
  final dev = config.links.where((l) => l.devPath != null).toList()
    ..sort((a, b) => a.package.compareTo(b.package));
  if (dev.isEmpty) return null;

  final buffer = StringBuffer()
    ..writeln(
      '# Generated by the grid.dart domain (context: ${context.name}). '
      'Do not hand-edit.',
    )
    ..writeln('dependency_overrides:');
  for (final link in dev) {
    final declared = link.devPath!;
    final String path;
    if (context == PubLinkContext.worktree && !p.isAbsolute(declared)) {
      if (devRoot == null) {
        throw StateError(
          'PubLink "${link.package}" declares the relative dev path '
          '"$declared", which cannot resolve from a deep worktree without a '
          'devRoot to absolutize against (fail-closed — a broken override is '
          'worse than none).',
        );
      }
      if (!p.isAbsolute(devRoot)) {
        throw StateError(
          'devRoot "$devRoot" is relative — absolutizing '
          '"${link.package}: $declared" against it would yield a still-'
          'relative (broken) override (fail-closed).',
        );
      }
      path = p.normalize(p.join(devRoot, declared));
    } else {
      path = declared;
    }
    buffer
      ..writeln('  ${link.package}:')
      ..writeln('    path: ${_yamlQuote(path)}');
  }
  return buffer.toString();
}

/// The stable git-ref emission (ADR-0003 D2): each link that declares a git pin
/// resolves to a `git: {url, ref, path: packages/<pkg>}` override. A link with
/// a PARTIAL git pin (exactly one of [PubLink.gitUrl]/[PubLink.gitRef]) is a
/// LOUD [StateError] refusal — never a silent path fallback (D2 + the house
/// "guards LOUD or GONE"). A link with NEITHER git field contributes nothing:
/// its hosted/git pin in `pubspec.yaml` proper stands (ADR-0003 D5). No
/// git-pinned links → null (nothing to override; the caller clears a stale
/// generated file). Deterministic: git links emit sorted by package.
String? _gitOverridesFor(PubLinkConfig config) {
  final git = <PubLink>[];
  for (final link in config.links) {
    final hasUrl = link.gitUrl != null;
    final hasRef = link.gitRef != null;
    if (!hasUrl && !hasRef) continue;
    if (!hasUrl || !hasRef) {
      throw StateError(
        'PubLink "${link.package}" declares a PARTIAL git pin in the stable '
        'context (git_url: ${link.gitUrl}, git_ref: ${link.gitRef}) — a stable '
        'git dependency needs BOTH url and ref; refusing rather than silently '
        'falling back to a path override (fail-closed).',
      );
    }
    git.add(link);
  }
  git.sort((a, b) => a.package.compareTo(b.package));
  if (git.isEmpty) return null;

  final buffer = StringBuffer()
    ..writeln(
      '# Generated by the grid.dart domain '
      '(context: ${PubLinkContext.stable.name}). Do not hand-edit.',
    )
    ..writeln('dependency_overrides:');
  for (final link in git) {
    buffer
      ..writeln('  ${link.package}:')
      ..writeln('    git:')
      ..writeln('      url: ${_yamlQuote(link.gitUrl!)}')
      ..writeln('      ref: ${_yamlQuote(link.gitRef!)}')
      ..writeln('      path: ${_yamlQuote('packages/${link.package}')}');
  }
  return buffer.toString();
}

/// Emits a generated `pubspec_overrides.yaml` that exact-pins hosted versions.
///
/// The INVERSE of the dev/stable emitters above: instead of pointing a package
/// at a local path or a git ref, it nails it to ONE published version. The
/// release verb's declared-floors leg uses this to resolve a candidate against
/// the exact minimums its own `pubspec.yaml` promises, so a member used above a
/// declared floor fails loudly instead of riding a workspace path resolution.
///
/// Keys are validated as pub package names (via [PubLink.fromJson], so a
/// YAML-dangerous "name" can never reach the emitter), values must parse as
/// exact semantic versions, and output is sorted by package (deterministic). An
/// empty map needs no override at all -> null.
String? pubspecOverridesForExactVersions(Map<String, String> versions) {
  if (versions.isEmpty) return null;
  final entries = versions.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final buffer = StringBuffer()
    ..writeln(
      '# Generated by release declared-floors validation. Do not hand-edit.',
    )
    ..writeln('dependency_overrides:');
  for (final entry in entries) {
    PubLink.fromJson(<String, Object?>{'package': entry.key});
    final exact = Version.parse(entry.value);
    buffer.writeln('  ${entry.key}: ${_yamlQuote(exact.toString())}');
  }
  return buffer.toString();
}

/// A single-quoted YAML scalar: content survives any YAML-hostile character
/// (embedded single quotes are doubled per the YAML spec).
String _yamlQuote(String value) => "'${value.replaceAll("'", "''")}'";
