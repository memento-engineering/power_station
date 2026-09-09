import 'dart:developer' as developer;

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        ApprovalRefused,
        ApprovalStamped,
        ApproveService,
        FilingRequirementRow,
        kApprovedAtKey,
        kApprovedByKey,
        kApprovedRevKey;
import 'package:grid_sdk/grid_sdk.dart' show WorkBeadKeys;

import '../github/issue_watch.dart';
import '../github/reconciler_event.dart';

/// The [GitHubIntakeRecord.kind] of a concluded workflow run.
const String kWorkflowRunKind = 'workflow run';

/// The `--actor` a self-approved workflow-run filing is recorded under.
const String kWorkflowRunActor = 'github-workflow';

/// Thin GitHub entity content projected into a bead.
///
/// The record is the SEAM: raw GitHub JSON never reaches the store, and the
/// store never reaches back for a rule. Everything the filing needs — the bead
/// type, its priority, its acceptance criterion, its metadata and whether the
/// seat asked for it to be approved — is decided by the projection and carried
/// here as values.
class GitHubIntakeRecord {
  /// Creates one normalized issue/pull-request intake record.
  const GitHubIntakeRecord({
    required this.nodeId,
    required this.kind,
    required this.repository,
    required this.number,
    required this.actor,
    required this.title,
    required this.body,
  }) : type = IssueType.chore,
       priority = 2,
       approve = false,
       acceptanceCriteria = null,
       openDuplicateFilter = null,
       _beadTitle = null,
       _description = null,
       _metadata = null;

  const GitHubIntakeRecord._({
    required this.nodeId,
    required this.kind,
    required this.repository,
    required this.number,
    required this.actor,
    required this.title,
    required this.body,
    required this.type,
    required this.priority,
    required this.approve,
    required this.acceptanceCriteria,
    required this.openDuplicateFilter,
    required String beadTitle,
    required String description,
    required Map<String, String> metadata,
  }) : _beadTitle = beadTitle,
       _description = description,
       _metadata = metadata;

  /// Creates the workflow-run arm: a BUG, not a chore.
  ///
  /// A red workflow run is a defect in the repository, and the type is what
  /// makes the bead driveable at all — the filing preflight's first row refuses
  /// an undriveable type, so a chore-typed run would be filed and then refused
  /// approval for a reason that has nothing to do with the run.
  factory GitHubIntakeRecord.workflowRun({
    required String nodeId,
    required String repository,
    required int runId,
    required int runNumber,
    required String workflowPath,
    required String workflowName,
    required String event,
    required String headBranch,
    required String headSha,
    required String conclusion,
    required String htmlUrl,
    required List<WorkflowRunFailedJob> failedJobs,
    required String validationPlan,
    required int priority,
    required bool approve,
  }) {
    final file = workflowPath.split('/').last;
    final jobs = <String>[
      for (final job in failedJobs)
        '- ${job.jobName} — first failed step: '
            '${job.failedStepName ?? 'not reported'}',
    ];
    // A run with no failed job still needs a falsifiable checkbox, and the
    // workflow is the only name left to give it.
    final named = failedJobs.isEmpty
        ? workflowName
        : failedJobs.map((job) => job.jobName).join(', ');
    return GitHubIntakeRecord._(
      nodeId: nodeId,
      kind: kWorkflowRunKind,
      repository: repository,
      number: runNumber,
      actor: kWorkflowRunActor,
      title: workflowName,
      body: htmlUrl,
      type: IssueType.bug,
      priority: priority,
      approve: approve,
      beadTitle:
          '[GitHub workflow $repository $file#$runNumber] '
          '$workflowName failed on $headBranch ($event)',
      description: <String>[
        'GitHub workflow $workflowName concluded $conclusion on $headBranch '
            'in $repository.',
        'Run: $htmlUrl',
        'Head sha: $headSha',
        'Event: $event',
        'Conclusion: $conclusion',
        '',
        if (jobs.isEmpty) 'GitHub reported no failed job for this run.',
        if (jobs.isNotEmpty) 'Failed jobs:',
        ...jobs,
      ].join('\n'),
      acceptanceCriteria:
          '- [ ] AC-1 — $named succeeds again for $workflowName on '
          '$headBranch; falsifier: `$validationPlan`',
      openDuplicateFilter: <String, String>{
        'github.workflow_path': workflowPath,
        'github.head_branch': headBranch,
      },
      metadata: <String, String>{
        'github.node_id': nodeId,
        'github.kind': kWorkflowRunKind,
        'github.repository': repository,
        'github.actor': kWorkflowRunActor,
        'github.run_id': '$runId',
        'github.workflow_path': workflowPath,
        'github.head_branch': headBranch,
        'github.head_sha': headSha,
        'github.conclusion': conclusion,
        WorkBeadKeys.validationPlan: validationPlan,
      },
    );
  }

  /// GitHub's stable node id for the observed entity.
  final String nodeId;

  /// Human-readable entity kind, e.g. `issue` or [kWorkflowRunKind].
  final String kind;

  /// `OWNER/REPOSITORY` the entity belongs to.
  final String repository;

  /// The issue/pull number, or the run number for a workflow run.
  final int number;

  /// The GitHub identity credited with the entity.
  final String actor;

  /// The entity's own title.
  final String title;

  /// The entity's own body.
  final String body;

  /// The bead type this record is filed as.
  final IssueType type;

  /// The bead priority this record is filed at.
  final int priority;

  /// Whether the seat's rule asked for a SELF filing to be approved.
  final bool approve;

  /// The single acceptance checkbox, or null when the arm files none.
  final String? acceptanceCriteria;

  /// The metadata equality that suppresses a SECOND filing while an earlier
  /// bead for the same subject is still OPEN, or null when the arm files every
  /// distinct entity.
  final Map<String, String>? openDuplicateFilter;

  final String? _beadTitle;
  final String? _description;
  final Map<String, String>? _metadata;

  /// The stable foreign identity the correlation read dedupes on.
  String get externalRef => 'github:$nodeId';

  /// The bead title.
  String get beadTitle =>
      _beadTitle ?? '[GitHub $kind $repository#$number] $title';

  /// The bead description.
  String get description =>
      _description ??
      [
        'GitHub $kind opened by @$actor in $repository#$number.',
        'GitHub node_id: $nodeId',
        if (body.isNotEmpty) '',
        if (body.isNotEmpty) body,
      ].join('\n');

  /// The bead metadata, written PER KEY through the merge channel.
  Map<String, String> get metadata =>
      _metadata ??
      <String, String>{
        'github.node_id': nodeId,
        'github.kind': kind,
        'github.repository': repository,
        'github.actor': actor,
      };
}

/// The `github.watch.*` metadata key naming the watched repository.
const String kIssueWatchRepositoryKey = 'github.watch.repository';

/// The `github.watch.*` metadata key naming the watched issue number.
const String kIssueWatchNumberKey = 'github.watch.issue_number';

/// The `github.watch.*` metadata key naming the watched issue's node id.
const String kIssueWatchNodeIdKey = 'github.watch.issue_node_id';

/// The `github.watch.*` metadata key naming the last projected observation.
const String kIssueWatchObservationKey = 'github.watch.last_observation';

/// The `github.watch.*` metadata key naming what last happened.
const String kIssueWatchChangeKey = 'github.watch.change';

/// The `github.watch.*` metadata key naming the issue's current state.
const String kIssueWatchStateKey = 'github.watch.state';

/// The `github.watch.*` metadata key naming the issue's current state reason.
const String kIssueWatchStateReasonKey = 'github.watch.state_reason';

/// The `github.watch.*` metadata key naming the issue's `updated_at`.
const String kIssueWatchUpdatedAtKey = 'github.watch.updated_at';

/// The [GitHubIssueWatchUpdate.change] value carried by a COMMENT.
///
/// A reply is not one of [GitHubIssueWatchChange]'s eight transitions, and
/// borrowing one of their spellings for it would make the metadata lie.
const String kIssueWatchCommentedChange = 'commented';

/// One watched-issue observation, projected onto the bead that CAUSED it.
///
/// Beside [GitHubIntakeRecord] and deliberately unlike it: intake CREATES or
/// correlates a bead by external ref, while a watch has a bead already — the
/// one whose work filed the issue — and only ever reopens and annotates it.
class GitHubIssueWatchUpdate {
  /// Creates one watch update.
  const GitHubIssueWatchUpdate({
    required this.beadId,
    required this.repository,
    required this.issueNumber,
    required this.issueNodeId,
    required this.observationId,
    required this.actor,
    required this.change,
    required this.state,
    required this.stateReason,
    required this.updatedAt,
    required this.url,
    required this.headline,
    required this.detail,
  });

  /// The bead whose work caused the watched issue to be filed.
  final String beadId;

  /// `OWNER/REPOSITORY` of the watched issue.
  final String repository;

  /// The watched issue's number.
  final int issueNumber;

  /// GitHub's stable node id for the watched issue.
  final String issueNodeId;

  /// The observation this update was projected from.
  final String observationId;

  /// The login credited with the comment or transition, or null when GitHub
  /// named nobody.
  final String? actor;

  /// The wire spelling of what happened — a [GitHubIssueWatchChange] or
  /// [kIssueWatchCommentedChange].
  final String change;

  /// The issue's state as of this observation, or null when the observation
  /// did not observe it.
  ///
  /// A COMMENT does not move the issue and carries no state: writing one here
  /// would assert `open` for a reply on a closed issue, and clearing one would
  /// erase what the last transition established. Null does NEITHER.
  final String? state;

  /// The issue's state reason as of this observation, or null when it has
  /// none.
  final String? stateReason;

  /// The issue's `updated_at` as of this observation.
  final DateTime updatedAt;

  /// The addressable page for this observation, or null when it has none.
  final String? url;

  /// The one-line summary the appended note leads with.
  final String headline;

  /// The observation's own text — a comment body, or the state it landed in.
  final String detail;

  /// The DETERMINISTIC note appended to the originating bead.
  ///
  /// Deterministic so the same observation replayed after a crash appends
  /// identical text: the delivered-id ledger is what stops a second append,
  /// and a timestamped or randomized note would make a duplicate invisible to
  /// a reader comparing them.
  String get note => <String>[
    'GitHub watch $repository#$issueNumber: $headline',
    if (actor != null && actor != kIssueWatchResourceActor) 'By: @$actor',
    if (url case final link?) 'URL: $link',
    if (state case final value?)
      if (stateReason case final reason?)
        'State: $value ($reason)'
      else
        'State: $value',
    'Observation: $observationId',
    '',
    detail,
  ].join('\n');

  /// The `github.watch.*` keys written through the merge channel.
  Map<String, String> get metadata => <String, String>{
    kIssueWatchRepositoryKey: repository,
    kIssueWatchNumberKey: '$issueNumber',
    kIssueWatchNodeIdKey: issueNodeId,
    kIssueWatchObservationKey: observationId,
    kIssueWatchChangeKey: change,
    kIssueWatchUpdatedAtKey: updatedAt.toUtc().toIso8601String(),
    if (state case final value?) kIssueWatchStateKey: value,
    if (stateReason case final reason?) kIssueWatchStateReasonKey: reason,
  };

  /// The metadata keys this update REMOVES.
  ///
  /// The three approval-stamp keys always — a bead reopened by an external
  /// reply is no longer a filing anyone approved — plus
  /// [kIssueWatchStateReasonKey] when a STATE observation carries no reason, so
  /// a reopened issue does not keep the reason it was closed with.
  List<String> get unsetMetadata => <String>[
    kApprovedByKey,
    kApprovedAtKey,
    kApprovedRevKey,
    if (state != null && stateReason == null) kIssueWatchStateReasonKey,
  ];
}

/// Upserts GitHub intake records by stable node id.
abstract interface class GitHubIntakeStore {
  /// Creates an OPEN bead or updates its existing correlated bead.
  Future<void> upsert(GitHubIntakeRecord record);

  /// Reopens and annotates the bead one watched-issue observation belongs to.
  Future<void> appendIssueWatch(GitHubIssueWatchUpdate update);
}

/// bd-CLI implementation of [GitHubIntakeStore].
///
/// Every spawn rides [BdCliService] over the injected [BdRunner], so this
/// surface inherits beads_dart's bd compatibility rails — the corpus replay,
/// the fixture-drift audit, and the exact-argv pins in
/// `beads_dart/test/services/bd_cli_service_test.dart` — instead of
/// hand-building argv that no rail covers (bead `pow-0nvg`).
///
/// **Metadata is written per key, never as one whole object.** The intake keys
/// ride [BdCliService.update]'s merge channel (one set-metadata flag per key),
/// whose server-side merge overwrites named keys and preserves absent ones.
/// bd's whole-object create-time metadata form REPLACES the map, which would
/// clobber the `validation_plan` and approval-stamp keys other writers own on
/// the same bead (`the_grid#bd-create-metadata-rides-a-follow-up-update`).
///
/// **Intake beads are filed OPEN, with no parking date.** Absence of the
/// approve verb's `grid.approved_*` stamp IS the pending state: it is
/// readiness-based rather than time-based, and it never fires on its own
/// (`power_station#github-intake-files-open-and-unstamped`). This store passes
/// no date argument and writes no label.
///
/// **This store never writes an approval key.** A human's issue or pull stays
/// unstamped exactly as before. A workflow run of the seat's OWN repository is
/// SELF authority (`power_station#own-workflow-failures-are-self-approved`),
/// and when its rule says so this store CALLS [ApproveService] — the same verb
/// a human runs, with the same four-row filing preflight — under the actor
/// [kWorkflowRunActor]. `grid_assets`'s `lib/src/filing/approve_command.dart`
/// remains the ONLY writer of `grid.approved_by` / `grid.approved_at` /
/// `grid.approved_rev`; a bead whose preflight fails is left OPEN and
/// unstamped with the refusal in its notes.
final class BdGitHubIntakeStore implements GitHubIntakeStore {
  /// Creates a store over the shared bounded runner.
  ///
  /// [approvals], [workRoot] and [stateRoot] wire the approval half. All three
  /// are optional because a composition that files nothing self-authored needs
  /// none of them — but a record that ASKS for approval without them is a
  /// wiring bug and is refused LOUDLY rather than filed unstamped in silence.
  BdGitHubIntakeStore(
    BdRunner runner, {
    ApproveService? approvals,
    String? workRoot,
    String? stateRoot,
  }) : _bd = BdCliService(runner),
       _approvals = approvals,
       _workRoot = workRoot,
       _stateRoot = stateRoot;

  final BdCliService _bd;
  final ApproveService? _approvals;
  final String? _workRoot;
  final String? _stateRoot;

  /// Reopens [GitHubIssueWatchUpdate.beadId] and annotates it, in ONE update.
  ///
  /// It targets the ORIGINATING bead exactly — it never creates a bead, never
  /// correlates one by external ref, and never opens a second store. A watched
  /// issue already has the work that caused it; filing a fresh bead for a reply
  /// would detach the answer from the question.
  ///
  /// The same update UNSETS all three approval-stamp keys and never calls
  /// [ApproveService]. An issue in a repository we do not control, and every
  /// commenter on it, is EXTERNAL — the self-approval authority the seat holds
  /// is workflow-run-only and is not extended here — so the bead lands back
  /// exactly where human intake leaves one: OPEN and unstamped.
  @override
  Future<void> appendIssueWatch(GitHubIssueWatchUpdate update) => _bd.update(
    update.beadId,
    status: BeadStatus.open,
    appendNotes: update.note,
    mergeMetadata: update.metadata,
    unsetMetadata: update.unsetMetadata,
    verifyTextRoundTrip: false,
  );

  @override
  Future<void> upsert(GitHubIntakeRecord record) async {
    final correlated = (await _bd.listScope(
      externalRef: record.externalRef,
      includeClosed: true,
    )).beads;
    if (correlated.length > 1) {
      throw StateError('multiple beads correlate to ${record.externalRef}');
    }
    if (correlated case [final bead]) {
      if (bead.id.isEmpty) {
        throw const BdParseException('correlated bead has no string id');
      }
      await _write(
        bead.id,
        record,
        title: record.beadTitle,
        description: record.description,
      );
      await _approve(bead.id, record);
      return;
    }
    if (await _openSubjectBead(record) case final existing?) {
      developer.log(
        'GitHub intake left ${record.externalRef} unfiled: $existing is still '
        'OPEN for the same subject ${record.openDuplicateFilter}',
        name: 'github_grid_assets.intake',
      );
      return;
    }
    final id = await _bd.create(
      title: record.beadTitle,
      type: record.type,
      priority: record.priority,
      description: record.description,
      externalRef: record.externalRef,
    );
    await _write(id, record);
    await _approve(id, record);
  }

  /// The id of an OPEN bead already filed for this record's subject, or null.
  ///
  /// A fresh run is a fresh node id, so the external-ref correlation above
  /// cannot see it — without this read the station would file one bead per
  /// night for one unfixed workflow. Appending to the existing bead instead is
  /// deliberately NOT done: a note on a stamped bead evicts its live round.
  Future<String?> _openSubjectBead(GitHubIntakeRecord record) async {
    final filter = record.openDuplicateFilter;
    if (filter == null) return null;
    final open = (await _bd.listScope(
      type: record.type,
      status: BeadStatus.open,
      metadataFields: filter,
    )).beads;
    return open.isEmpty ? null : open.first.id;
  }

  /// The record's acceptance criterion and per-key metadata, in ONE update.
  ///
  /// [BdCliService.update]'s text round-trip verification is declined because
  /// it costs a `bd show`, and `bd show` writes `.beads/last-touched` and
  /// self-triggers the workspace watcher — this write happens on the
  /// reconciler's own poll cadence. The argv-transport guard that refuses text
  /// bd cannot carry runs BEFORE execution either way and is untouched.
  Future<void> _write(
    String id,
    GitHubIntakeRecord record, {
    String? title,
    String? description,
  }) => _bd.update(
    id,
    title: title,
    description: description,
    acceptanceCriteria: record.acceptanceCriteria,
    mergeMetadata: record.metadata,
    verifyTextRoundTrip: false,
  );

  /// Stamps [beadId] through the approve VERB when the record asks for it.
  Future<void> _approve(String beadId, GitHubIntakeRecord record) async {
    if (!record.approve) return;
    final approvals = _approvals;
    final workRoot = _workRoot;
    if (approvals == null || workRoot == null) {
      throw StateError(
        'a $kWorkflowRunKind record asked for approval but this store was '
        'built with no ApproveService and no work root',
      );
    }
    final outcome = await approvals.approve(
      storeRoot: workRoot,
      beadId: beadId,
      actor: kWorkflowRunActor,
      stateRoot: _stateRoot,
    );
    switch (outcome) {
      case ApprovalStamped():
        return;
      case ApprovalRefused(:final reason, :final report):
        // The failing ROWS, not just the verb's summary: the note is what an
        // operator reads to know which field to correct, and "has failing
        // rows" names none of them.
        final failing = <String>[
          for (final row
              in report?.requirements ?? const <FilingRequirementRow>[])
            if (!row.passed) '${row.requirement.wire}: ${row.detail}',
        ];
        await _bd.update(
          beadId,
          appendNotes: <String>[
            'Self-approval refused by the filing preflight: $reason.',
            ...failing,
            'The bead stays OPEN and unstamped until the filing is corrected.',
          ].join('\n'),
          verifyTextRoundTrip: false,
        );
    }
  }
}
