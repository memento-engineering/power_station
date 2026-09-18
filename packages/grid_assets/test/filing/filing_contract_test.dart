import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:crypto/crypto.dart';
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

/// The dependencies row of one evaluation — the only row this bead moves.
FilingRequirementRow _dependencies(
  Bead bead,
  List<BeadDependency> edges, {
  Set<String>? armed,
}) => const FilingContract()
    .evaluate(
      bead,
      edges,
      evidence: FilingEvidence.unavailable,
      armedSubstations: armed,
    )
    .requirements
    .singleWhere((row) => row.requirement == FilingRequirement.dependencies);

BeadDependency _blocks(String from, String to) =>
    BeadDependency(issueId: from, dependsOnId: to);

void main() {
  test('approval revision is deterministic and covers filing basis', () {
    const bead = Bead(
      id: 'pow-filed',
      title: 'A filed bead',
      issueType: IssueType.task,
      priority: 2,
      description: 'The work',
      design: 'The chosen approach',
      acceptanceCriteria: '- [ ] checked',
      notes: 'operator context',
      specId: 'pow-spec',
      metadata: {'validation_plan': 'dart test'},
    );
    const one = BeadDependency(issueId: 'pow-filed', dependsOnId: 'pow-one');
    const two = BeadDependency(issueId: 'pow-filed', dependsOnId: 'pow-two');
    const external = BeadDependency(
      issueId: 'pow-filed',
      dependsOnId: 'external:the_grid:tg-xh5d',
    );

    String rev(
      Bead subject,
      List<BeadDependency> edges, [
      Set<String>? armed,
    ]) => const FilingContract()
        .evaluate(
          subject,
          edges,
          evidence: FilingEvidence.unavailable,
          armedSubstations: armed,
        )
        .approvalRevision;

    final baseline = rev(bead, const [one, two]);
    expect(baseline, startsWith(kFilingApprovalRevisionPrefix));
    expect(
      baseline.substring(kFilingApprovalRevisionPrefix.length),
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );

    // The basis STATED, not pinned as an opaque golden hash: the expected map
    // is written out whole, so equality proves its MEMBERSHIP, its key ORDER
    // and its row shape at once. It also proves an ABSENCE — one extra member
    // moves the digest, so a basis that still carried the retired link-proof
    // member (or grew any other) could not match this.
    String digestOf(Map<String, Object?> basis) =>
        '$kFilingApprovalRevisionPrefix'
        '${sha256.convert(utf8.encode(jsonEncode(basis)))}';
    Map<String, Object?> basisOver(List<Map<String, Object?>> rows) => {
      'id': 'pow-filed',
      'title': 'A filed bead',
      'description': 'The work',
      'design': 'The chosen approach',
      'acceptanceCriteria': '- [ ] checked',
      'notes': 'operator context',
      'specId': 'pow-spec',
      'issueType': 'task',
      'priority': 2,
      'validationPlan': 'dart test',
      'dependencies': rows,
    };

    expect(
      baseline,
      digestOf(
        basisOver(const [
          {'id': 'pow-one', 'kind': 'local'},
          {'id': 'pow-two', 'kind': 'local'},
        ]),
      ),
    );

    // An `external:` row rides that SAME basis, typed and sorted after the
    // local ones. It is bd's row and nothing else: no link bead is read, and
    // no proof-of-link member is digested beside it.
    expect(
      rev(bead, const [one, two, external], const {'the_grid'}),
      digestOf(
        basisOver(const [
          {'id': 'pow-one', 'kind': 'local'},
          {'id': 'pow-two', 'kind': 'local'},
          {'id': 'external:the_grid:tg-xh5d', 'kind': 'external'},
        ]),
      ),
    );

    // Equivalent input in a different ORDER is the same basis.
    expect(rev(bead, const [two, one]), baseline);
    expect(rev(bead, const [two, one, two]), baseline);

    // Every covered field moves it.
    for (final changed in <Bead>[
      bead.copyWith(id: 'pow-elsewhere'),
      bead.copyWith(title: 'A renamed bead'),
      bead.copyWith(description: 'Different work'),
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

    // The ROWS bd holds are the dependency basis — each one independently.
    expect(rev(bead, const [one]), isNot(baseline));
    expect(rev(bead, const [one, two, external]), isNot(baseline));

    // The ROSTER is the STATION's posture, never the bead's content: arming a
    // substation must not revoke a governor's approval of a bead nobody
    // edited, so it is excluded from the basis.
    expect(
      rev(bead, const [one, two, external], const {'the_grid'}),
      rev(bead, const [one, two, external], const {}),
    );
    expect(
      rev(bead, const [one, two, external], const {'the_grid'}),
      rev(bead, const [one, two, external]),
    );

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
      const FilingContract().evaluate(bead, const [
        one,
        two,
      ], evidence: FilingEvidence.unavailable).toJson(),
      containsPair('approval_revision', baseline),
    );
  });

  test('the dependencies row projects bd rows, and only bd rows', () {
    const bead = Bead(
      id: 'pow-filed',
      issueType: IssueType.task,
      description: 'The work',
      acceptanceCriteria: '- [ ] checked',
      metadata: {'validation_plan': 'dart test'},
    );
    final incoming = _blocks('pow-one', 'pow-filed');
    final unrelated = _blocks('pow-other', 'pow-two');
    const wrongType = BeadDependency(
      issueId: 'pow-filed',
      dependsOnId: 'pow-one',
      type: DependencyType.related,
    );

    // Directional and type-exact: an incoming edge, another bead's edge and a
    // non-blocking edge are not this bead's blockers.
    final foreign = _dependencies(bead, [incoming, unrelated, wrongType]);
    expect(foreign.passed, isTrue);
    expect(foreign.detail, 'bd holds no blocking dependency rows');

    // The bead's OWN outgoing blocking rows are the whole row, sorted.
    final held = _dependencies(bead, [
      _blocks('pow-filed', 'pow-two'),
      _blocks('pow-filed', 'pow-one'),
      incoming,
    ]);
    expect(held.passed, isTrue);
    expect(held.detail, 'bd dependency rows: pow-one, pow-two');
  });

  test(
    'AC-1: the hyphenated and spaced prose spellings project identically',
    () {
      const hyphenated = Bead(
        id: 'pow-filed',
        issueType: IssueType.task,
        description: 'Blocked-by: pow-x. Depends-on pow-y.',
        acceptanceCriteria: '- [ ] checked',
        metadata: {'validation_plan': 'dart test'},
      );
      final spaced = hyphenated.copyWith(
        description: 'Blocked by: pow-x. Depends on pow-y. Blocked on pow-z.',
      );

      // No row exists, so BOTH beads report the same empty projection — the
      // grammar that read one spelling and not the other is GONE.
      for (final subject in [hyphenated, spaced]) {
        final row = _dependencies(subject, const []);
        expect(row.passed, isTrue, reason: subject.description);
        expect(
          row.detail,
          'bd holds no blocking dependency rows',
          reason: subject.description,
        );
      }
      expect(
        _dependencies(hyphenated, const []).toJson(),
        _dependencies(spaced, const []).toJson(),
      );

      // And with ONE bd row they agree again: what bd holds is the answer, and
      // the prose — in either spelling — adds and subtracts nothing.
      final wired = [_blocks('pow-filed', 'pow-x')];
      expect(
        _dependencies(hyphenated, wired).toJson(),
        _dependencies(spaced, wired).toJson(),
      );
      expect(_dependencies(spaced, wired).detail, 'bd dependency rows: pow-x');

      // A receipt QUOTING the phrase mid-sentence is prose too — the refusal
      // that cost a round on 2026-09-13 cannot recur.
      final quoting = hyphenated.copyWith(
        description: "pow-pry0 carries a 'DEPENDS ON: tg-1n4y' receipt.",
      );
      expect(_dependencies(quoting, const []).passed, isTrue);
    },
  );

  test('AC-2: an external row resolves through the roster', () {
    const bead = Bead(
      id: 'pow-filed',
      issueType: IssueType.task,
      description: 'The work',
      acceptanceCriteria: '- [ ] checked',
      metadata: {'validation_plan': 'dart test'},
    );
    final rows = [
      _blocks('pow-filed', 'external:the_grid:tg-xh5d'),
      _blocks('pow-filed', 'pow-local'),
    ];

    // ARMED: an ordinary prerequisite, reported beside the local rows.
    final armed = _dependencies(bead, rows, armed: {'the_grid', 'space'});
    expect(armed.passed, isTrue);
    expect(
      armed.detail,
      'bd dependency rows: pow-local, external:the_grid:tg-xh5d (armed)',
    );

    // NOT ARMED: the Q4 hard refusal — blocked, named, and told what to do.
    final unarmed = _dependencies(bead, rows, armed: {'space'});
    expect(unarmed.passed, isFalse);
    expect(
      unarmed.detail,
      contains('external:the_grid:tg-xh5d names "the_grid"'),
    );
    expect(unarmed.detail, contains('armed: space'));
    expect(unarmed.detail, contains('arm that substation'));

    // NO ROSTER: fail-closed too, and the detail says WHICH condition it is.
    final unconsulted = _dependencies(bead, rows);
    expect(unconsulted.passed, isFalse);
    expect(unconsulted.detail, contains('no station roster was supplied'));
    expect(unconsulted.detail, isNot(contains('does not arm')));

    // A malformed `external:` spelling is read as a LOCAL id — the same thing
    // bd does with it, never a third reading. The parser is bd's OWN
    // ([ExternalDepRef], beads_dart): this package holds no second one.
    expect(ExternalDepRef.parse('external:the_grid:'), isNull);
    expect(ExternalDepRef.parse('external:solo'), isNull);
    expect(ExternalDepRef.parse('pow-plain'), isNull);
    expect(
      _dependencies(bead, [_blocks('pow-filed', 'external:solo')]).detail,
      'bd dependency rows: external:solo',
    );
  });

  test('the projection exposes its rows for the explainer and the checks', () {
    final projection = DependencyProjection.of(
      beadId: 'pow-filed',
      dependencies: [
        _blocks('pow-filed', 'pow-b'),
        _blocks('pow-filed', 'pow-a'),
        _blocks('pow-filed', 'external:the_grid:cap'),
        _blocks('pow-other', 'pow-c'),
      ],
      armedSubstations: const {'the_grid'},
    );

    expect(projection.local, ['pow-a', 'pow-b']);
    expect(projection.external.single.ref.project, 'the_grid');
    expect(projection.external.single.ref.capability, 'cap');
    expect(projection.external.single.resolution, ExternalResolution.armed);
    expect(projection.passed, isTrue);
    expect(projection.basis, [
      {'id': 'pow-a', 'kind': 'local'},
      {'id': 'pow-b', 'kind': 'local'},
      {'id': 'external:the_grid:cap', 'kind': 'external'},
    ]);
  });

  test('source is read-only, ONE spawn, and carries external rows', () async {
    final runner = _RecordingBdRunner([
      '{"schema_version":1,"data":['
          '{"id":"pow-filed","title":"filed","issue_type":"task",'
          '"dependencies":['
          '{"issue_id":"pow-filed","depends_on_id":"pow-one",'
          '"type":"blocks"},'
          '{"issue_id":"pow-filed",'
          '"depends_on_id":"external:the_grid:tg-xh5d","type":"blocks"}'
          ']}]}',
    ]);
    final source = ExactSubstationBeadSource(runnerFor: (_) => runner);

    final read = await source.readExact(
      storeRoot: '/work/power_station',
      beadId: 'pow-filed',
    );

    expect(read.bead!.id, 'pow-filed');
    expect(read.dependencies.map((edge) => edge.dependsOnId), [
      'pow-one',
      'external:the_grid:tg-xh5d',
    ]);
    // ONE record read. `bd dep list` is NOT spawned: it RESOLVES each row to
    // the issue record it points at, and an `external:` target has no issue in
    // this store, so the resolving surface returns the cross-project rows not
    // at all.
    const query = ['query', 'id=pow-filed', '--all', '--json'];
    expect(runner.argvs, hasLength(1));
    expect(
      runner.argvs.single,
      anyOf(equals(query), equals([...query, '--limit', '0'])),
    );
    expect(
      runner.argvs.expand((argv) => argv),
      isNot(contains(anyOf('show', 'dep', 'create', 'update', 'close'))),
    );
  });

  test('an absent bead costs the same one read and reports missing', () async {
    final runner = _RecordingBdRunner(['{"schema_version":1,"data":[]}']);
    final read = await ExactSubstationBeadSource(
      runnerFor: (_) => runner,
    ).readExact(storeRoot: '/work/power_station', beadId: 'pow-gone');

    expect(read.bead, isNull);
    expect(read.dependencies, isEmpty);
    expect(runner.argvs, hasLength(1));
  });

  test('the record surface is reconciled against the resolving one', () async {
    // No rows on the record surface is AMBIGUOUS — a store with no dependency
    // rows, or a surface that stopped carrying them. beads_dart's own control
    // ([externalDepRowsFrom]) decides it, and only this case spawns the second
    // read.
    final empty = _RecordingBdRunner([
      '{"schema_version":1,"data":['
          '{"id":"pow-filed","title":"filed","issue_type":"task"}]}',
      '{"schema_version":1,"data":[]}',
    ]);
    final read = await ExactSubstationBeadSource(
      runnerFor: (_) => empty,
    ).readExact(storeRoot: '/work/power_station', beadId: 'pow-filed');

    expect(read.bead!.id, 'pow-filed');
    expect(read.dependencies, isEmpty);
    expect(empty.argvs.map((argv) => argv.first), ['query', 'dep']);

    // A record surface that DROPPED rows the resolving read still holds is a
    // silent ADMISSION of blocked work, so it REFUSES.
    final dropped = _RecordingBdRunner([
      '{"schema_version":1,"data":['
          '{"id":"pow-filed","title":"filed","issue_type":"task"}]}',
      '{"schema_version":1,"data":['
          '{"issue_id":"pow-filed","depends_on_id":"pow-one",'
          '"type":"blocks"}]}',
    ]);
    await expectLater(
      ExactSubstationBeadSource(
        runnerFor: (_) => dropped,
      ).readExact(storeRoot: '/work/power_station', beadId: 'pow-filed'),
      throwsA(isA<BdExternalDepSurfaceUnavailable>()),
    );
  });

  test('a duplicate id in the exact read is LOUD', () async {
    final runner = _RecordingBdRunner([
      '{"schema_version":1,"data":['
          '{"id":"pow-filed","issue_type":"task"},'
          '{"id":"pow-filed","issue_type":"task"}]}',
    ]);
    await expectLater(
      ExactSubstationBeadSource(
        runnerFor: (_) => runner,
      ).readExact(storeRoot: '/work/power_station', beadId: 'pow-filed'),
      throwsA(isA<StateError>()),
    );
  });
}
