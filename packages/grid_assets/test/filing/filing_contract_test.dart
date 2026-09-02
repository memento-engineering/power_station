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
