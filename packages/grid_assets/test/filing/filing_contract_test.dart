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
