import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

class _RecordingBdRunner implements BdRunner {
  _RecordingBdRunner(this.replies);

  final List<String> replies;
  final List<List<String>> argvs = [];
  var _reply = 0;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(args);
    return BdResult(exitCode: 0, stdout: replies[_reply++], stderr: '');
  }
}

void main() {
  test('approval revision is deterministic and covers filing basis', () {
    const bead = Bead(
      id: 'pow-filed',
      title: 'A filed bead',
      issueType: IssueType.task,
      priority: 2,
      description: 'Blocked by: pow-one\nDepends on pow-two',
      design: 'The chosen approach',
      acceptanceCriteria: '- [ ] checked',
      notes: 'operator context',
      specId: 'pow-spec',
      metadata: {'validation_plan': 'dart test'},
    );
    const one = BeadDependency(issueId: 'pow-filed', dependsOnId: 'pow-one');
    const two = BeadDependency(issueId: 'pow-filed', dependsOnId: 'pow-two');

    String rev(Bead subject, List<BeadDependency> edges) =>
        const FilingContract().evaluate(subject, edges).approvalRevision;

    final baseline = rev(bead, const [one, two]);
    expect(baseline, startsWith(kFilingApprovalRevisionPrefix));
    expect(
      baseline.substring(kFilingApprovalRevisionPrefix.length),
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );

    // The v1 basis SHAPE is FROZEN: every `grid.approved_rev` already written
    // is a digest over these keys, so the `linked` member stays in the basis
    // rather than being dropped, which would re-digest every approved bead in
    // every store. This fixture is wired LOCALLY, so its digest is byte-for-
    // byte the pre-cut value — the case the cut does NOT move. The case it
    // DOES move is pinned below in 'the cross-store shape re-digests'.
    // A GOLDEN digest, so a future edit to the basis cannot slip through as
    // "just a refactor": changing it revokes every standing approval and needs
    // a v2 prefix.
    expect(
      baseline,
      '${kFilingApprovalRevisionPrefix}0811d3b73e7a2fa4c3dbd079481ef28fc363'
      '864e6593d74a55b28810f825ab2d',
    );

    // Equivalent input in a different ORDER is the same basis.
    expect(rev(bead, const [two, one]), baseline);
    expect(rev(bead, const [two, one, two]), baseline);

    // Every covered field moves it.
    for (final changed in <Bead>[
      bead.copyWith(id: 'pow-elsewhere'),
      bead.copyWith(title: 'A renamed bead'),
      bead.copyWith(description: 'Blocked by: pow-one\nDepends on pow-three'),
      bead.copyWith(design: 'A different approach'),
      bead.copyWith(acceptanceCriteria: '- [ ] checked twice'),
      bead.copyWith(notes: 'different context'),
      bead.copyWith(specId: 'pow-other-spec'),
      bead.copyWith(issueType: IssueType.chore),
      bead.copyWith(priority: 1),
      bead.copyWith(metadata: const {'validation_plan': 'dart analyze'}),
      bead.copyWith(metadata: const {}),
    ]) {
      expect(
        rev(changed, const [one, two]),
        isNot(baseline),
        reason: changed.toString(),
      );
    }

    // Each dependency PROOF is covered independently: the named blocker and
    // the local outgoing edge.
    expect(rev(bead, const [one]), isNot(baseline));
    expect(rev(bead, const []), isNot(baseline));

    // Lifecycle motion, ownership and the receipt itself are EXCLUDED, so
    // writing the stamp can never invalidate the stamp it writes.
    for (final untouched in <Bead>[
      bead.copyWith(status: BeadStatus.closed),
      bead.copyWith(assignee: 'nico', owner: 'nico'),
      bead.copyWith(
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026, 2),
        closedAt: DateTime.utc(2026, 3),
      ),
      bead.copyWith(labels: const ['grid.approved']),
      bead.copyWith(
        metadata: {
          ...bead.metadata,
          kApprovedByKey: 'nico',
          kApprovedAtKey: '2026-09-02T14:30:00.000Z',
          kApprovedRevKey: baseline,
        },
      ),
    ]) {
      expect(
        rev(untouched, const [one, two]),
        baseline,
        reason: untouched.toString(),
      );
    }

    // A report with no bead to evaluate carries no revision.
    expect(FilingReport.missing('pow-gone').approvalRevision, isEmpty);
    expect(
      const FilingContract().evaluate(bead, const [one, two]).toJson(),
      containsPair('approval_revision', baseline),
    );
  });

  test('the cross-store shape re-digests and its dependency row moves', () {
    // The ONE shape this adoption is not neutral on. Pre-cut, a bead approved
    // with `--state-root` CONSULTED and a matching open link bead digested
    // `linked: true` per wired blocker, AND took the linked blocker's store
    // prefix into `knownPrefixes`, which is what made a DIGITLESS foreign id
    // readable as an id. The state-store link surface is deleted
    // (grid_engine 0.4.0-dev.3, the_grid#447), so both inputs are gone and the
    // digest of such a bead MOVES — its standing stamp is stale and
    // `approve`/`unpark` refuse it until a governor re-approves.
    //
    // The pre-cut literals below were MEASURED on 2026-09-13 by running the
    // pre-cut `FilingContract.evaluate(bead, [], linkedBlockers: {...})` from
    // the primary checkout on `main` over this exact fixture. They are here so
    // the change is a pinned fact rather than a claim, and so a later attempt
    // to "restore digest stability" fails loudly instead of quietly.
    const bead = Bead(
      id: 'space-adopt',
      title: 'Adopt the wave',
      issueType: IssueType.task,
      priority: 1,
      description:
          'BLOCKED BY: the wave tags (pow-abaw + pow-f6pc). '
          'Cross-store; wired by the governor.',
      design: 'Bump the floors',
      acceptanceCriteria: '- [ ] AC-1',
      notes: 'governor context',
      specId: 'space-spec',
      metadata: {'validation_plan': 'dart test'},
    );
    const preCutRevision =
        '${kFilingApprovalRevisionPrefix}1acd2d4d399b3c8f4fd93c015c455b077157'
        '038a786396a4e47ce2f0d17b73c0';

    final report = const FilingContract().evaluate(
      bead,
      const <BeadDependency>[],
    );

    // It re-digests: the standing stamp no longer matches this evaluation.
    expect(report.approvalRevision, isNot(preCutRevision));
    expect(
      report.approvalRevision,
      '${kFilingApprovalRevisionPrefix}5f17fb5f253c41e36cda05a5cd23d1ef5e08'
      '968c005355d3c44676dc07d14812',
    );

    // The row passed pre-cut on the link proof; it now fails CLOSED on the
    // digit-tailed foreign id, which is still read as an id.
    final dependency = report.requirements.singleWhere(
      (row) => row.requirement == FilingRequirement.dependencies,
    );
    expect(report.passed, isFalse);
    expect(dependency.passed, isFalse);
    expect(dependency.detail, 'missing outgoing blocks edges: pow-f6pc');

    // And the DIGITLESS foreign id is not named at all any more: with no local
    // edge in its store, `pow` is not a known prefix and `abaw` carries no
    // digit. That row passes VACUOUSLY — the cut is fail-closed only for the
    // tokens the grammar still recognises, which is why pow-f6pc
    // (power_station#330) retires the grammar for bd's own dependency rows.
    final foreignOnly = const FilingContract().evaluate(
      bead.copyWith(
        description:
            'BLOCKED BY: pow-abaw. Cross-store; wired by the '
            'governor.',
      ),
      const <BeadDependency>[],
    );
    final foreignRow = foreignOnly.requirements.singleWhere(
      (row) => row.requirement == FilingRequirement.dependencies,
    );
    expect(foreignRow.passed, isTrue);
    expect(foreignRow.detail, 'no local blockers named');
  });

  test('dependency requirement is exact and directional', () {
    const bead = Bead(
      id: 'pow-filed',
      issueType: IssueType.task,
      description: 'Blocked by: pow-one\nDepends on pow-two',
      acceptanceCriteria: '- [ ] checked',
      metadata: {'validation_plan': 'dart test'},
    );
    const incoming = BeadDependency(
      issueId: 'pow-one',
      dependsOnId: 'pow-filed',
    );
    const unrelated = BeadDependency(
      issueId: 'pow-other',
      dependsOnId: 'pow-two',
    );
    const wrongType = BeadDependency(
      issueId: 'pow-filed',
      dependsOnId: 'pow-one',
      type: DependencyType.related,
    );
    const one = BeadDependency(issueId: 'pow-filed', dependsOnId: 'pow-one');
    const two = BeadDependency(issueId: 'pow-filed', dependsOnId: 'pow-two');

    FilingRequirementRow dependency(List<BeadDependency> edges) =>
        const FilingContract()
            .evaluate(bead, edges)
            .requirements
            .singleWhere(
              (row) => row.requirement == FilingRequirement.dependencies,
            );

    expect(dependency([incoming, unrelated, wrongType]).passed, isFalse);
    expect(dependency([one]).detail, contains('pow-two'));
    expect(dependency([one, two]).passed, isTrue);
    expect(
      const FilingContract()
          .evaluate(bead.copyWith(description: 'No local ordering.'), const [])
          .requirements
          .last
          .passed,
      isTrue,
    );
  });

  test('blockers are named at sentence scope, dotted ids intact', () {
    const bead = Bead(
      id: 'pow-n6n.2',
      issueType: IssueType.task,
      description:
          'Child 2 of epic pow-n6n. Depends on child pow-n6n.1 (local). '
          'BLOCKED on tg-89y8 across stores.',
      acceptanceCriteria: '- [ ] checked',
      metadata: {'validation_plan': 'dart test'},
    );
    const local = BeadDependency(
      issueId: 'pow-n6n.2',
      dependsOnId: 'pow-n6n.1',
    );

    FilingRequirementRow dependency(List<BeadDependency> edges) =>
        const FilingContract()
            .evaluate(bead, edges)
            .requirements
            .singleWhere(
              (row) => row.requirement == FilingRequirement.dependencies,
            );

    expect(dependency(const []).passed, isFalse);
    expect(
      dependency(const []).detail,
      allOf(contains('pow-n6n.1'), contains('tg-89y8')),
    );
    expect(
      dependency(const [local]).detail,
      allOf(isNot(contains('pow-n6n.1')), contains('tg-89y8')),
    );
    expect(
      dependency(const [
        local,
        BeadDependency(issueId: 'pow-n6n.2', dependsOnId: 'tg-89y8'),
      ]).passed,
      isTrue,
    );
    expect(
      const FilingContract()
          .evaluate(
            bead.copyWith(
              description: 'The design depends on whether we ship.',
            ),
            const [],
          )
          .requirements
          .last
          .passed,
      isTrue,
    );
  });

  test('a named FOREIGN blocker is missing, fail-closed', () {
    const bead = Bead(
      id: 'pow-n6n.2',
      issueType: IssueType.task,
      description:
          'Depends on child pow-n6n.1 (local). '
          'BLOCKED on tg-89y8 across stores.',
      acceptanceCriteria: '- [ ] checked',
      metadata: {'validation_plan': 'dart test'},
    );
    const local = BeadDependency(
      issueId: 'pow-n6n.2',
      dependsOnId: 'pow-n6n.1',
    );

    FilingRequirementRow dependency(List<BeadDependency> edges) =>
        const FilingContract()
            .evaluate(bead, edges)
            .requirements
            .singleWhere(
              (row) => row.requirement == FilingRequirement.dependencies,
            );

    // There is no second lookup any more: grid_engine's state-store link
    // surface is deleted (the_grid#447), so a foreign id is judged by the
    // bead's OWN outgoing edges like every other named blocker — and an
    // unwired one is MISSING, never quietly excused as unchecked.
    expect(
      dependency(const []).detail,
      'missing outgoing blocks edges: pow-n6n.1, tg-89y8',
    );
    expect(dependency(const []).passed, isFalse);
    expect(
      dependency(const [local]).detail,
      'missing outgoing blocks edges: tg-89y8',
    );
    expect(dependency(const [local]).passed, isFalse);

    // A local `blocks` edge to the foreign id wires it.
    expect(
      dependency(const [
        local,
        BeadDependency(issueId: 'pow-n6n.2', dependsOnId: 'tg-89y8'),
      ]).detail,
      'all named local blockers are wired',
    );
  });

  test('source is read-only by construction', () async {
    final runner = _RecordingBdRunner([
      '{"schema_version":1,"data":['
          '{"id":"pow-filed","title":"filed","issue_type":"task"}]}',
      '{"schema_version":1,"data":['
          '{"issue_id":"pow-filed","depends_on_id":"pow-one",'
          '"type":"blocks"}]}',
    ]);
    final source = ExactSubstationBeadSource(runnerFor: (_) => runner);

    final read = await source.readExact(
      storeRoot: '/work/power_station',
      beadId: 'pow-filed',
    );

    expect(read.bead!.id, 'pow-filed');
    const query = ['query', 'id=pow-filed', '--all', '--json'];
    expect(runner.argvs, hasLength(2));
    expect(
      runner.argvs.first,
      anyOf(equals(query), equals([...query, '--limit', '0'])),
    );
    expect(runner.argvs.last, ['dep', 'list', 'pow-filed', '--json']);
    expect(
      runner.argvs.expand((argv) => argv),
      isNot(contains(anyOf('show', 'create', 'update', 'close'))),
    );
  });

  test('source accepts current dependency-bead rows', () async {
    final runner = _RecordingBdRunner([
      '{"schema_version":1,"data":['
          '{"id":"pow-filed","title":"filed","issue_type":"task"}]}',
      '{"schema_version":1,"data":['
          '{"id":"pow-one","title":"blocker",'
          '"dependency_type":"blocks"}]}',
    ]);
    final source = ExactSubstationBeadSource(runnerFor: (_) => runner);

    final read = await source.readExact(
      storeRoot: '/work/power_station',
      beadId: 'pow-filed',
    );

    expect(read.dependencies, [
      isA<BeadDependency>()
          .having((edge) => edge.issueId, 'issueId', 'pow-filed')
          .having((edge) => edge.dependsOnId, 'dependsOnId', 'pow-one')
          .having((edge) => edge.type, 'type', DependencyType.blocks),
    ]);
    expect(runner.argvs, hasLength(2));
  });
}
