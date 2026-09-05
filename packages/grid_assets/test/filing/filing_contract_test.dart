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

    String rev(
      Bead subject,
      List<BeadDependency> edges, [
      Set<String>? linked,
    ]) => const FilingContract()
        .evaluate(subject, edges, linkedBlockers: linked)
        .approvalRevision;

    final baseline = rev(bead, const [one, two]);
    expect(baseline, startsWith(kFilingApprovalRevisionPrefix));
    expect(
      baseline.substring(kFilingApprovalRevisionPrefix.length),
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );

    // Equivalent input in a different ORDER is the same basis.
    expect(rev(bead, const [two, one]), baseline);
    expect(rev(bead, const [two, one, two]), baseline);
    expect(
      rev(bead, const [one, two], const {'pow-two', 'pow-one'}),
      rev(bead, const [one, two], const {'pow-one', 'pow-two'}),
    );

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

    // Each dependency PROOF is covered independently: the named blocker, the
    // local outgoing edge, and the linked-blocker proof.
    expect(rev(bead, const [one]), isNot(baseline));
    expect(rev(bead, const [one], const {'pow-two'}), isNot(baseline));
    expect(rev(bead, const [one, two], const {'pow-two'}), isNot(baseline));
    expect(rev(bead, const [], const {'pow-one', 'pow-two'}), isNot(baseline));

    // The basis records the proofs FOUND, not the posture of the lookup: an
    // unconsulted state store and a consulted one holding no matching link
    // both witness "no linked proof", so they agree.
    expect(rev(bead, const [one, two], const {}), baseline);

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

    FilingRequirementRow dependency(
      List<BeadDependency> edges,
      Set<String> linked,
    ) => const FilingContract()
        .evaluate(bead, edges, linkedBlockers: linked)
        .requirements
        .singleWhere(
          (row) => row.requirement == FilingRequirement.dependencies,
        );

    expect(dependency(const [], const {}).passed, isFalse);
    expect(
      dependency(const [], const {}).detail,
      allOf(contains('pow-n6n.1'), contains('tg-89y8')),
    );
    expect(
      dependency(const [local], const {}).detail,
      allOf(isNot(contains('pow-n6n.1')), contains('tg-89y8')),
    );
    expect(dependency(const [local], const {'tg-89y8'}).passed, isTrue);
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

  test('an unconsulted state store yields UNCHECKED, never missing', () {
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

    FilingRequirementRow dependency(
      List<BeadDependency> edges, {
      Set<String>? linked,
    }) => const FilingContract()
        .evaluate(bead, edges, linkedBlockers: linked)
        .requirements
        .singleWhere(
          (row) => row.requirement == FilingRequirement.dependencies,
        );

    // UNCONSULTED (null): only the bead's own store can be called missing.
    expect(
      dependency(const []).detail,
      'missing outgoing blocks edges: pow-n6n.1; '
      '$kUnconsultedCrossStoreDetail',
    );
    expect(dependency(const []).passed, isFalse);
    expect(dependency(const [local]).detail, kUnconsultedCrossStoreDetail);
    expect(dependency(const [local]).detail, isNot(contains('tg-89y8')));

    // CONSULTED and empty: the same foreign id IS genuinely missing.
    expect(
      dependency(const [local], linked: const {}).detail,
      'missing outgoing blocks edges: tg-89y8',
    );

    // A local `blocks` edge to the foreign id needs no lookup at all.
    expect(
      dependency(const [
        local,
        BeadDependency(issueId: 'pow-n6n.2', dependsOnId: 'tg-89y8'),
      ]).detail,
      'all named local blockers are wired',
    );
  });

  test(
    'an open link bead wires a foreign blocker, a malformed one does not',
    () async {
      final runner = _RecordingBdRunner([
        '{"schema_version":1,"data":['
            '{"id":"tgdog-l1","issue_type":"link","status":"open",'
            '"metadata":{"grid.link.from":"pow-n6n.2",'
            '"grid.link.to":"tg-89y8","grid.link.type":"blocks"}},'
            '{"id":"tgdog-l2","issue_type":"link","status":"open",'
            '"metadata":{"grid.link.from":"pow-n6n.2",'
            '"grid.link.type":"blocks"}},'
            '{"id":"tgdog-l3","issue_type":"link","status":"open",'
            '"metadata":{"grid.link.from":"pow-other",'
            '"grid.link.to":"tg-zzz","grid.link.type":"blocks"}}]}',
      ]);

      final wired = await CrossLinkBlockerSource(
        runnerFor: (_) => runner,
      ).wiredFor(stateRoot: '/work/home/.grid', beadId: 'pow-n6n.2');

      expect(wired, {'tg-89y8'});
      expect(runner.argvs.single, [
        'list',
        '-t',
        'link',
        '--status',
        'open',
        '--json',
        '--limit',
        '0',
      ]);
    },
  );

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
