/// The ONE adapter from this pack's live artifacts onto the shadow selector's
/// normalized evidence contract (bead `pow-1nl.1.1`).
///
/// `committee_selection.dart` declares [CommitteeSelectionEvidence] and knows
/// nothing about where facts come from; this library is the only place that
/// knows the discovery gather, the dossier and the pinned diff. That split is
/// what keeps the policy free of `discovery.dart`, `committee.dart`,
/// `specify.dart` and `docs_committee.dart`, and it is why the pinned-diff path
/// arrives as an injected [CommitteePinnedDiffPath] value rather than an import.
///
/// **The two stages read different things.**
///
///  - `spec_review` ([buildSpecReviewSelectionEvidence]) consumes the
///    round-stamped [DiscoveryAnchors] and [DiscoveryDossier] the discovery
///    circuit already gathered ONCE
///    (`power_station#discovery-evidence-is-gathered-once-and-projected`) —
///    intent, acceptance, resolved path anchors, decision lookups, prior art,
///    context and flags. It never includes a diff: at spec time there is none.
///  - `code_review` ([buildCodeReviewSelectionEvidence]) consumes those same
///    facts PLUS the actual pinned `origin/<base>...HEAD` diff — the complete
///    file's SHA-256, and the changed target paths parsed out of its
///    `diff --git` headers.
///
/// **A missing artifact is a FACT, never an exception and never synthetic clean
/// evidence.** Every unresolved input names itself in
/// [CommitteeSelectionEvidence.missingEvidenceIds], so a shape the policy could
/// not see is visibly unknown rather than quietly empty.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'committee_selection.dart';
import 'discovery.dart';

/// Matches ONE unified-diff file header; the `b/` side is the CHANGED target.
final RegExp _diffTarget = RegExp(
  r'^diff --git a/(\S+) b/(\S+)$',
  multiLine: true,
);

/// Reads one stage's evidence out of the live worktree.
///
/// Best-effort by construction: the discovery readers already degrade an
/// absent/corrupt artifact to null, and the pinned diff is read through the
/// same posture. Nothing here throws for a missing input.
class DiscoveryCommitteeSelectionEvidenceSource
    implements CommitteeSelectionEvidenceSource {
  /// Creates the source over the injected [pinnedDiffPathFor] deriver, with the
  /// two discovery readers overridable so an offline fixture never touches a
  /// real filesystem.
  const DiscoveryCommitteeSelectionEvidenceSource({
    required this.pinnedDiffPathFor,
    this.readAnchors = readDiscoveryAnchors,
    this.readDossier = readDiscoveryDossier,
  });

  /// Derives the absolute pinned-diff path under a workspace.
  final CommitteePinnedDiffPath pinnedDiffPathFor;

  /// Reads the round's deterministic gather.
  final DiscoveryAnchors? Function(String workspaceDir) readAnchors;

  /// Reads the round's curated dossier.
  final DiscoveryDossier? Function(String workspaceDir) readDossier;

  @override
  CommitteeSelectionEvidence read({
    required CommitteeStage stage,
    required String workBeadId,
    required String workspaceDir,
  }) {
    if (workspaceDir.isEmpty || !Directory(workspaceDir).existsSync()) {
      return CommitteeSelectionEvidence(
        stage: stage,
        workBeadId: workBeadId,
        round: 0,
        missingEvidenceIds: const ['workspace'],
      );
    }
    final anchors = _best(() => readAnchors(workspaceDir));
    final dossier = _best(() => readDossier(workspaceDir));
    return switch (stage) {
      CommitteeStage.specReview => buildSpecReviewSelectionEvidence(
        workBeadId: workBeadId,
        anchors: anchors,
        dossier: dossier,
      ),
      CommitteeStage.codeReview => buildCodeReviewSelectionEvidence(
        workBeadId: workBeadId,
        anchors: anchors,
        dossier: dossier,
        pinnedDiff: _best(() => _readPinnedDiff(workspaceDir)),
      ),
    };
  }

  String? _readPinnedDiff(String workspaceDir) {
    final file = File(pinnedDiffPathFor(workspaceDir));
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  static T? _best<T>(T? Function() read) {
    try {
      return read();
    } on Object {
      return null;
    }
  }
}

/// The `spec_review` evidence — the round-stamped discovery facts, with NO diff.
CommitteeSelectionEvidence buildSpecReviewSelectionEvidence({
  required String workBeadId,
  required DiscoveryAnchors? anchors,
  required DiscoveryDossier? dossier,
}) => _build(
  stage: CommitteeStage.specReview,
  workBeadId: workBeadId,
  anchors: anchors,
  dossier: dossier,
  pinnedDiff: null,
  includeDiff: false,
);

/// The `code_review` evidence — the same discovery facts PLUS the actual pinned
/// diff: the complete file's digest and its changed target paths.
CommitteeSelectionEvidence buildCodeReviewSelectionEvidence({
  required String workBeadId,
  required DiscoveryAnchors? anchors,
  required DiscoveryDossier? dossier,
  required String? pinnedDiff,
}) => _build(
  stage: CommitteeStage.codeReview,
  workBeadId: workBeadId,
  anchors: anchors,
  dossier: dossier,
  pinnedDiff: pinnedDiff,
  includeDiff: true,
);

/// The changed TARGET paths a unified diff names, normalized, deduplicated and
/// sorted. Only `diff --git a/<path> b/<path>` headers are read — never a hunk.
List<String> committeeChangedPathsIn(String diff) {
  final paths = <String>{};
  for (final match in _diffTarget.allMatches(diff)) {
    final target = match.group(2)?.trim() ?? '';
    if (target.isEmpty || target == '/dev/null') continue;
    paths.add(target.startsWith('./') ? target.substring(2) : target);
  }
  return paths.toList()..sort();
}

CommitteeSelectionEvidence _build({
  required CommitteeStage stage,
  required String workBeadId,
  required DiscoveryAnchors? anchors,
  required DiscoveryDossier? dossier,
  required String? pinnedDiff,
  required bool includeDiff,
}) {
  final missing = <String>[];
  final usable = _verify(
    workBeadId: workBeadId,
    anchors: anchors,
    dossier: dossier,
    missing: missing,
  );
  final gather = usable.anchors;
  final curated = usable.dossier;

  final intent = <String>[];
  final acceptance = <String>[];
  final paths = <String>[];
  final decisions = <String>[];
  final priorArt = <String>[];
  final context = <String>[];
  final flags = <String>[];
  var truncated = false;

  if (gather != null) {
    for (final field in gather.beadFields) {
      final id = '${field.field.wire}:${field.evidence.id}';
      switch (field.field) {
        case BeadCitationField.title:
        case BeadCitationField.description:
        case BeadCitationField.design:
          intent.add(id);
        case BeadCitationField.acceptanceCriteria:
          acceptance.add(id);
        case BeadCitationField.notes:
          break;
      }
      truncated |= _isTruncated(field.evidence.state);
      if (_isGap(field.evidence.state)) {
        missing.add('bead-field:${field.field.wire}');
      }
    }
    for (final anchor in gather.anchors) {
      paths.add(
        '${anchor.anchor}|${anchor.resolved}|${anchor.contents.digest}',
      );
      truncated |= _isTruncated(anchor.contents.state);
      if (_isGap(anchor.contents.state)) missing.add('anchor:${anchor.anchor}');
    }
    for (final lookup in gather.decisionLookups) {
      decisions.add(
        'surface:${lookup.surface}|${lookup.state.name}|${lookup.id}',
      );
      for (final entry in lookup.decisions) {
        decisions.add('decision:${entry.body.id}');
      }
      truncated |= lookup.truncated || _isTruncated(lookup.state);
      if (_isGap(lookup.state)) missing.add('decisions:${lookup.surface}');
    }
    for (final query in gather.priorArtQueries) {
      priorArt.add('query:${query.query}|${query.state.name}|${query.id}');
      for (final hit in query.hits) {
        priorArt.add('hit:${hit.evidenceId}');
      }
      truncated |= query.truncated || _isTruncated(query.state);
      if (_isGap(query.state)) missing.add('prior-art:${query.query}');
    }
    truncated |= gather.anchorsTruncated || gather.symbolsTruncated;
    if (gather.anchorsTruncated) missing.add('anchors:clipped');
    if (gather.symbolsTruncated) missing.add('symbols:clipped');
  }

  if (curated != null) {
    for (final note in curated.context) {
      context.add(
        'context:${committeeDigest({'note': note.note, 'source': note.source})}',
      );
    }
    for (final flag in curated.flags) {
      flags.add('flag:${committeeDigest(flag.toJson())}');
    }
    for (final departure in curated.departures) {
      decisions.add('departure:${committeeDigest(departure.toJson())}');
    }
    for (final lens in curated.missingLenses) {
      missing.add('lens:$lens');
    }
  }

  var pinnedDigest = '';
  final changedPaths = <String>[];
  if (includeDiff) {
    if (pinnedDiff == null) {
      missing.add('pinned-diff');
    } else {
      pinnedDigest = sha256.convert(utf8.encode(pinnedDiff)).toString();
      changedPaths.addAll(committeeChangedPathsIn(pinnedDiff));
      if (changedPaths.isEmpty) missing.add('pinned-diff:no-targets');
    }
  }

  final round = gather?.round ?? -1;
  if (round < 0) missing.add('round');

  return CommitteeSelectionEvidence(
    stage: stage,
    workBeadId: workBeadId,
    round: round < 0 ? 0 : round,
    intent: intent,
    acceptance: acceptance,
    paths: paths,
    decisions: decisions,
    priorArt: priorArt,
    context: context,
    flags: flags,
    changedPaths: changedPaths,
    pinnedDiffDigest: pinnedDigest,
    missingEvidenceIds: missing,
    truncated: truncated,
  );
}

/// Cross-checks the two artifacts before ANY fact is read off them.
///
/// A gather for another bead, a dossier for another bead, a dossier whose
/// embedded gather is not the one on disk, or a dossier citing evidence the
/// gather does not carry are all REFUSED (the artifact contributes nothing) and
/// named — never half-read.
({DiscoveryAnchors? anchors, DiscoveryDossier? dossier}) _verify({
  required String workBeadId,
  required DiscoveryAnchors? anchors,
  required DiscoveryDossier? dossier,
  required List<String> missing,
}) {
  var gather = anchors;
  var curated = dossier;
  if (gather == null) {
    missing.add('anchors');
  } else if (workBeadId.isNotEmpty && gather.workBeadId != workBeadId) {
    missing.add('anchors:work-bead-mismatch');
    gather = null;
  }
  if (curated == null) {
    missing.add('dossier');
    return (anchors: gather, dossier: null);
  }
  if (workBeadId.isNotEmpty && curated.workBeadId != workBeadId) {
    missing.add('dossier:work-bead-mismatch');
    return (anchors: gather, dossier: null);
  }
  if (gather != null &&
      (curated.anchors.round != gather.round ||
          curated.anchors.workBeadId != gather.workBeadId)) {
    missing.add('dossier:anchors-mismatch');
    return (anchors: gather, dossier: null);
  }
  if (gather != null && !gather.evidenceIds.containsAll(curated.evidenceIds)) {
    missing.add('dossier:evidence-id-mismatch');
    return (anchors: gather, dossier: null);
  }
  return (anchors: gather, dossier: curated);
}

bool _isTruncated(EvidenceState state) => switch (state) {
  EvidenceState.truncated => true,
  EvidenceState.complete ||
  EvidenceState.unavailable ||
  EvidenceState.failed => false,
};

bool _isGap(EvidenceState state) => switch (state) {
  EvidenceState.failed || EvidenceState.unavailable => true,
  EvidenceState.complete || EvidenceState.truncated => false,
};
