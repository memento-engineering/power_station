/// The DART-domain linkage SERVICE — the reusable lib layer behind the exported
/// Command (the layering rule: a Command is a thin adapter; a Flutter app must
/// be able to execute this via UI, so the logic lives HERE, never on the
/// Command).
///
/// Stateless I/O (predictable-flutter Services): decode the `grid.dart`
/// envelope off a bead's metadata → derive the `pubspec_overrides.yaml`
/// content for the context (pure, `pubspecOverridesFor`) → write/remove the
/// file at the target workspace root. Pub honors `pubspec_overrides.yaml` at
/// the WORKSPACE ROOT (resolution is workspace-wide), so [workspaceDir] must be
/// the checkout/worktree root, not a member package dir.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/domain_envelope.dart';
import 'dart_domain.dart';
import 'pub_links.dart';

/// The overrides file name pub honors beside a pubspec.
const String kPubspecOverridesFile = 'pubspec_overrides.yaml';

/// What applying the linkage did — sealed so callers (the Command, a future
/// Flutter UI) render exhaustively.
sealed class LinkOutcome {
  const LinkOutcome();
}

/// Overrides were written for [packages] at [file].
class LinkApplied extends LinkOutcome {
  /// Wraps the written [file] + the overridden [packages].
  const LinkApplied({required this.file, required this.packages});

  /// The written `pubspec_overrides.yaml` path.
  final String file;

  /// The packages the file overrides (sorted).
  final List<String> packages;
}

/// No overrides apply for this context; an existing generated file was
/// [removed] (a stable apply clears a stale dev link — but never a file this
/// domain didn't generate).
class LinkCleared extends LinkOutcome {
  /// Wraps whether a file was actually [removed].
  const LinkCleared({required this.removed});

  /// True when an existing generated overrides file was deleted.
  final bool removed;
}

/// The bead declares no `grid.dart` config — nothing was touched.
class LinkNoConfig extends LinkOutcome {
  /// The no-config outcome.
  const LinkNoConfig();
}

/// The envelope could not be used (incompatible pack version / malformed) —
/// FAIL-CLOSED: nothing was touched.
class LinkRefused extends LinkOutcome {
  /// Wraps the [reason] (diagnostics).
  const LinkRefused(this.reason);

  /// Why the envelope was refused.
  final String reason;
}

/// Applies a work bead's declared pub linkage to a checkout (stateless; safe
/// to construct anywhere — a CLI Command, a Flutter interactor).
class DartLinkService {
  /// Creates the service.
  const DartLinkService();

  /// Decodes the `grid.dart` envelope from [metadata] and applies its pub
  /// linkage for [context] at [workspaceDir] (the workspace ROOT):
  ///
  /// - links with dev paths → writes [kPubspecOverridesFile] (worktree context
  ///   absolutizes relative paths against [devRoot] — fail-closed without one);
  /// - stable / no dev links → removes a previously GENERATED overrides file
  ///   (never one this domain didn't write — a hand-authored file is left
  ///   alone and reported un-removed);
  /// - no `grid.dart` on the bead → touches nothing ([LinkNoConfig]);
  /// - incompatible/malformed envelope → touches nothing ([LinkRefused]).
  Future<LinkOutcome> apply({
    required Map<String, dynamic> metadata,
    required PubLinkContext context,
    required String workspaceDir,
    String? devRoot,
  }) async {
    final plan = _plan(
      metadata: metadata,
      context: context,
      workspaceDir: workspaceDir,
      devRoot: devRoot,
    );
    switch (plan) {
      case _Done(:final outcome):
        return outcome;
      case _Write(:final file, :final content, :final packages):
        if (content == null) return _clear(file);
        await file.writeAsString(content);
        return LinkApplied(file: file.path, packages: packages);
    }
  }

  /// The synchronous counterpart of [apply] — for a call site that cannot
  /// await (e.g. [ProcessCapability.spawn], which returns a `RuntimeConfig`
  /// directly, not a `Future`). Same decode → derive → write/clear logic;
  /// sync `dart:io` calls in place of async ones. Never partial: a refusal
  /// touches nothing, exactly as [apply].
  LinkOutcome applySync({
    required Map<String, dynamic> metadata,
    required PubLinkContext context,
    required String workspaceDir,
    String? devRoot,
  }) {
    final plan = _plan(
      metadata: metadata,
      context: context,
      workspaceDir: workspaceDir,
      devRoot: devRoot,
    );
    switch (plan) {
      case _Done(:final outcome):
        return outcome;
      case _Write(:final file, :final content, :final packages):
        if (content == null) return _clearSync(file);
        file.writeAsStringSync(content);
        return LinkApplied(file: file.path, packages: packages);
    }
  }

  /// The shared decode+derive half of [apply]/[applySync] (pure aside from
  /// the [pubspecOverridesFor] call, which throws only on a malformed
  /// relative/devRoot combination): resolves either an early [_Done] outcome
  /// (absent/incompatible/malformed/refused) or a [_Write] plan for the
  /// caller's IO tail to execute (sync or async).
  _Plan _plan({
    required Map<String, dynamic> metadata,
    required PubLinkContext context,
    required String workspaceDir,
    String? devRoot,
  }) {
    switch (decodeDartEnvelope(metadata)) {
      case DomainEnvelopeAbsent():
        return const _Done(LinkNoConfig());
      case DomainEnvelopeIncompatible(:final version):
        return _Done(
          LinkRefused(
            'grid.dart envelope written by an incompatible pack '
            '(assets_version $version; this pack reads $kDartAssetsVersion)',
          ),
        );
      case DomainEnvelopeMalformed(:final reason):
        return _Done(LinkRefused('grid.dart envelope malformed: $reason'));
      case DomainEnvelopeDecoded(:final config):
        final String? content;
        try {
          content = pubspecOverridesFor(config.pub, context, devRoot: devRoot);
        } on StateError catch (e) {
          return _Done(LinkRefused(e.message));
        }
        return _Write(
          File(p.join(workspaceDir, kPubspecOverridesFile)),
          content,
          [
            for (final l in config.pub.links)
              if (l.devPath != null) l.package,
          ]..sort(),
        );
    }
  }

  /// Removes [file] only when THIS domain generated it (the marker comment) —
  /// a hand-authored `pubspec_overrides.yaml` is never deleted, and anything
  /// unreadable (a dir/odd link in the file's place) is left alone rather than
  /// guessed at (fail-closed: when in doubt, don't delete).
  Future<LinkOutcome> _clear(File file) async {
    if (!file.existsSync()) return const LinkCleared(removed: false);
    final String head;
    try {
      head = await file
          .openRead(0, 128)
          .transform(const SystemEncoding().decoder)
          .join();
    } on FileSystemException {
      return const LinkCleared(removed: false);
    }
    if (!head.startsWith('# Generated by the grid.dart domain')) {
      return const LinkCleared(removed: false);
    }
    await file.delete();
    return const LinkCleared(removed: true);
  }

  /// The sync counterpart of [_clear].
  LinkOutcome _clearSync(File file) {
    if (!file.existsSync()) return const LinkCleared(removed: false);
    final String head;
    try {
      final raf = file.openSync();
      try {
        head = const SystemEncoding().decode(raf.readSync(128));
      } finally {
        raf.closeSync();
      }
    } on FileSystemException {
      return const LinkCleared(removed: false);
    }
    if (!head.startsWith('# Generated by the grid.dart domain')) {
      return const LinkCleared(removed: false);
    }
    file.deleteSync();
    return const LinkCleared(removed: true);
  }
}

/// The [DartLinkService._plan] result — either the outcome is already decided
/// ([_Done]) or the caller must execute the write/clear IO tail ([_Write]).
sealed class _Plan {
  const _Plan();
}

class _Done extends _Plan {
  const _Done(this.outcome);
  final LinkOutcome outcome;
}

/// [content] null means "clear [file] if THIS domain generated it"; non-null
/// means "write [content] to [file]", reporting [packages] on success.
class _Write extends _Plan {
  const _Write(this.file, this.content, this.packages);
  final File file;
  final String? content;
  final List<String> packages;
}
