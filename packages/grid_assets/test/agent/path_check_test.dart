import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

void main() {
  group('shellCommandExecutables', () {
    test('finds external commands after compound operators', () {
      expect(
        shellCommandExecutables(
          'cd packages/grid_assets && dart analyze && dart test',
        ),
        ['dart'],
      );
      expect(
        shellCommandExecutables(
          'dart test || rg failure | sed -n 1p; sh -c true',
        ),
        ['dart', 'rg', 'sed', 'sh'],
      );
    });

    test(
      'handles parentheses, assignments, duplicates, and builtin-only plans',
      () {
        expect(shellCommandExecutables('(FOO=bar dart test) && (rg failure)'), [
          'dart',
          'rg',
        ]);
        expect(shellCommandExecutables('dart analyze; dart test'), ['dart']);
        expect(
          shellCommandExecutables('cd someplace && export FOO=bar; wait'),
          isEmpty,
        );
      },
    );
  });

  group('pathCheckDiagnostic', () {
    test('labels candidates after an observed exit 127', () {
      expect(
        pathCheckDiagnostic('rg needle', 127),
        'exit 127 — candidate missing commands: rg',
      );
    });

    test('does not diagnose any other exit code', () {
      expect(pathCheckDiagnostic('rg needle', 1), isNull);
    });

    test('quote-heavy parsing is advisory only after exit 127', () {
      const plan = 'grep -E "(foo|bar)" && echo "\$(rg needle)"';
      expect(pathCheckDiagnostic(plan, 0), isNull);
      expect(
        pathCheckDiagnostic(plan, 127),
        startsWith('exit 127 — candidate missing commands: '),
      );
    });
  });
}
