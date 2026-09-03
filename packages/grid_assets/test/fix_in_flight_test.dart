// The fix-in-flight CARRY and the REFINEMENT flag (bead `pow-bhm`) — the two
// worktree channels a re-tuned committee round leaves behind, and the two
// briefs that read them.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

const _finding =
    'step 3 cites `the_grid#admission-authority-boundary` for a clause that '
    'lives in `power_station#landing-policy`';

FixInFlight _carry() => const FixInFlight(
  sessionRoot: 'tg-1',
  round: 0,
  lane: RespecLane(rubric: 'adr-alignment', grade: 'D', rationale: _finding),
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('carry'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the carry round-trips through the worktree file', () {
    writeFixInFlight(dir.path, _carry());
    final read = readFixInFlight(dir.path);
    expect(read, isNotNull);
    expect(read!.lane.rationale, _finding);
    expect(read.lane.rubric, 'adr-alignment');
    // A SIBLING of `.grid/critique/`, which clear-critique wipes each round.
    expect(fixInFlightPath(dir.path), endsWith('.grid/spec/fix-in-flight.json'));
    clearFixInFlight(dir.path);
    expect(readFixInFlight(dir.path), isNull);
  });

  test('a corrupt carry degrades to NO carry — never a throw', () {
    File(fixInFlightPath(dir.path))
      ..createSync(recursive: true)
      ..writeAsStringSync('{ not json');
    expect(readFixInFlight(dir.path), isNull);
  });

  test('the BUILD brief carries the finding VERBATIM and binds it', () {
    final brief = buildAgentBrief(
      bead('tg-1'),
      testWorkspace('tg-1', workspaceDir: dir.path, branch: 'grid/tg-1'),
      fixInFlight: _carry(),
    ).render();
    expect(brief, contains(_finding));
    expect(brief, contains('BINDING'));
  });

  test('no carry ⇒ the brief is unchanged', () {
    final brief = buildAgentBrief(
      bead('tg-1'),
      testWorkspace('tg-1', workspaceDir: dir.path, branch: 'grid/tg-1'),
    ).render();
    expect(brief, isNot(contains('Fix in flight')));
  });

  test('a code critic RE-CHECKS a live carry, and ignores an absent one', () {
    const cap = CriticCapability();
    String prompt() => cap.buildCriticPrompt(
      bead('tg-1'),
      'regression-risk',
      'tg-1/review/regression-risk',
      dir.path,
      round: 0,
    );
    expect(prompt(), isNot(contains('Fix in flight')));
    writeFixInFlight(dir.path, _carry());
    expect(prompt(), contains(_finding));
    expect(prompt(), contains('Fix in flight'));
  });

  test('the refinement flag round-trips and renders for the operator', () {
    const flag = RefinementFlag(
      sessionRoot: 'tg-1',
      round: 0,
      notes: [
        RefinementNote(
          rubric: 'coherence',
          finding: 'tg-yau duplicates this bead; tg-9kk deps on the duplicate',
        ),
      ],
    );
    writeRefinementFlag(dir.path, flag);
    expect(readRefinementFlag(dir.path)!.notes.single.rubric, 'coherence');
    expect(renderRefinementFlag(flag), contains('tg-yau'));
    expect(renderRefinementFlag(flag), contains('not a spec defect'));
    clearRefinementFlag(dir.path);
    expect(readRefinementFlag(dir.path), isNull);
  });
}
