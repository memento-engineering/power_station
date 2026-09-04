// The `grid:` block is this pack's SINGLE authored asset declaration. Pins: the
// closed selector grammar and its grid_sdk mapping, the refusals (each naming
// the asset and the field), the ATOMIC two-output write, `--check` staleness,
// and the committed outputs being a fresh render of the committed block.
// Offline; the block reader is exercised through an injected Fake path probe.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A Fake artifact probe: exactly [present] resolves, nothing else does.
class FakePathProbe {
  FakePathProbe(this.present);

  final Set<String> present;

  bool call(String path) => present.contains(path);
}

const String _skillPath = 'extension/x/SKILL.md';

String _pubspec(String assets) =>
    'name: grid_assets\n'
    'grid:\n'
    '  assets:\n$assets'
    '  station_overlay:\n'
    '    mappings:\n'
    '      claude: .claude\n';

String _skill({String? selector, String audience = 'agent'}) =>
    '    - id: probe\n'
    '      kind: skill\n'
    '      description: "A probe."\n'
    '      audience: $audience\n'
    '      visibility: public\n'
    '${selector == null ? '' : '      selector: "$selector"\n'}'
    '      artifacts:\n'
    '        - target: claude\n'
    '          path: $_skillPath\n';

GridBlock _parse(String assets) => parseGridBlock(
  pubspecYaml: _pubspec(assets),
  pathExists: FakePathProbe({_skillPath}).call,
);

/// The real package root, walked up from the cwd like the loader's own walk.
String _packageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(dir.path, 'extension', 'rubrics')).existsSync()) {
      return dir.path;
    }
    final nested = Directory(p.join(dir.path, 'packages', 'grid_assets'));
    if (nested.existsSync()) return nested.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not locate packages/grid_assets from ${Directory.current.path}');
}

void main() {
  group('the selector grammar is CLOSED and maps onto grid_sdk', () {
    test('omission means unknown and renders EXACTLY as `any` does', () {
      final omitted = _parse(_skill());
      final declared = _parse(_skill(selector: 'any'));
      expect(omitted.assets.single.selector, isA<AlwaysApplies>());
      expect(declared.assets.single.selector, isA<AlwaysApplies>());
      expect(
        selectorExpression(omitted.assets.single.selector),
        selectorExpression(declared.assets.single.selector),
      );
      expect(omitted.undeclaredSelectorAssetIds, ['grid_assets/skill/probe']);
      expect(declared.undeclaredSelectorAssetIds, isEmpty);
    });

    test('`unknown` is spellable and identical to omission', () {
      expect(
        _parse(_skill(selector: 'unknown')).assets.single.selector,
        isA<AlwaysApplies>(),
      );
    });

    test(
      'the parameterised and path tokens map to their grid_sdk variants',
      () {
        expect(
          _parse(
            _skill(selector: 'dart-package:grid_sdk'),
          ).assets.single.selector,
          isA<RequiresPackage>().having(
            (s) => s.packageName,
            'packageName',
            'grid_sdk',
          ),
        );
        expect(
          _parse(_skill(selector: 'decision-register')).assets.single.selector,
          isA<RequiresPath>().having(
            (s) => s.relativePath,
            'relativePath',
            'docs/decisions',
          ),
        );
        expect(
          _parse(_skill(selector: 'station')).assets.single.selector,
          isA<RequiresPath>().having(
            (s) => s.relativePath,
            'relativePath',
            '.grid',
          ),
        );
      },
    );

    test('`never` is refused LOUD, naming the absent grid_sdk variant', () {
      expect(
        () => _parse(_skill(selector: 'never')),
        throwsA(
          isA<GridBlockException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('asset "skill/probe"'),
              contains('selector:'),
              contains('no unsatisfiable variant'),
            ),
          ),
        ),
      );
    });

    test('an unrecognised token and a stray argument are both refused', () {
      expect(
        () => _parse(_skill(selector: 'sometimes')),
        throwsA(
          isA<GridBlockException>().having(
            (e) => e.message,
            'message',
            contains('unrecognised selector "sometimes"'),
          ),
        ),
      );
      expect(
        () => _parse(_skill(selector: 'station:extra')),
        throwsA(
          isA<GridBlockException>().having(
            (e) => e.message,
            'message',
            contains('"station" takes no argument'),
          ),
        ),
      );
      expect(
        () => _parse(_skill(selector: 'dart-package:')),
        throwsA(
          isA<GridBlockException>().having(
            (e) => e.message,
            'message',
            contains('requires a package name'),
          ),
        ),
      );
    });
  });

  group('every malformed field is refused, naming the asset and the field', () {
    void refuses(String assets, Matcher message) => expect(
      () => _parse(assets),
      throwsA(
        isA<GridBlockException>().having((e) => e.message, 'message', message),
      ),
    );

    test('an unrecognised kind', () {
      refuses(
        '    - id: probe\n'
        '      kind: widget\n'
        '      description: "A probe."\n'
        '      artifacts:\n'
        '        - target: claude\n'
        '          path: $_skillPath\n',
        allOf(
          contains('unknown/probe'),
          contains('unrecognised kind "widget"'),
        ),
      );
    });

    test('an unrecognised audience and an unrecognised visibility', () {
      refuses(
        _skill(audience: 'robot'),
        allOf(
          contains('asset "skill/probe"'),
          contains('unrecognised audience "robot"'),
        ),
      );
      refuses(
        '    - id: probe\n'
        '      kind: skill\n'
        '      description: "A probe."\n'
        '      visibility: secret\n'
        '      artifacts:\n'
        '        - target: claude\n'
        '          path: $_skillPath\n',
        contains('unrecognised visibility "secret"'),
      );
    });

    test('an unrecognised delivery target', () {
      refuses(
        '    - id: probe\n'
        '      kind: skill\n'
        '      description: "A probe."\n'
        '      artifacts:\n'
        '        - target: emacs\n'
        '          path: $_skillPath\n',
        allOf(
          contains('artifacts[0].target'),
          contains('unrecognised target "emacs"'),
        ),
      );
    });

    test('a path that does not exist', () {
      refuses(
        '    - id: probe\n'
        '      kind: skill\n'
        '      description: "A probe."\n'
        '      artifacts:\n'
        '        - target: claude\n'
        '          path: extension/nope/SKILL.md\n',
        allOf(
          contains('artifacts[0].path'),
          contains('"extension/nope/SKILL.md" does not exist'),
        ),
      );
    });

    test('a duplicate logical identity', () {
      refuses(
        _skill() + _skill(),
        allOf(
          contains('asset "skill/probe"'),
          contains('duplicate logical identity'),
        ),
      );
    });

    test('a duplicate delivery target within ONE asset', () {
      refuses(
        '    - id: probe\n'
        '      kind: skill\n'
        '      description: "A probe."\n'
        '      artifacts:\n'
        '        - target: claude\n'
        '          path: $_skillPath\n'
        '        - target: claude\n'
        '          path: $_skillPath\n',
        allOf(
          contains('artifacts[1].target'),
          contains('duplicate delivery target "claude"'),
        ),
      );
    });
  });

  group('the MCP mirror carries only MCP concepts', () {
    test('human renders as operator, extension/ is stripped, and agent- and '
        'settings-kind assets are NOT mirrored', () {
      final block = parseGridBlock(
        pubspecYaml: _pubspec(
          '${_skill(audience: 'human')}'
          '    - id: governor\n'
          '      kind: agent\n'
          '      description: "The seat."\n'
          '      audience: human\n'
          '      artifacts:\n'
          '        - target: claude\n'
          '          path: $_skillPath\n',
        ),
        pathExists: FakePathProbe({_skillPath}).call,
      );
      final yaml = renderMcpConfig(block);
      expect(yaml, contains(kGridBlockGeneratedMarker));
      expect(yaml, contains('audience: operator'));
      expect(yaml, contains('path: x/SKILL.md'));
      expect(yaml, isNot(contains('id: governor')));
      expect(yaml, isNot(contains('kind:')));
      expect(yaml, isNot(contains('selector:')));
    });
  });

  group('the committed outputs ARE a fresh render of the committed block', () {
    final root = _packageRoot();

    test('the generator reports current (--check exits 0)', () {
      final out = StringBuffer();
      expect(
        runGridAssetsGenerator(packageRoot: root, check: true, out: out),
        0,
        reason: out.toString(),
      );
      expect(out.toString(), contains('UNDECLARED selector'));
    });

    test('the real block declares 28 assets across five kinds', () {
      final block = parseGridBlock(
        pubspecYaml: File(p.join(root, 'pubspec.yaml')).readAsStringSync(),
        pathExists: (relative) =>
            File(p.join(root, relative)).existsSync() ||
            Directory(p.join(root, relative)).existsSync(),
      );
      expect(block.assets, hasLength(28));
      expect(block.assets.map((a) => a.assetKey.kind).toSet(), {
        AssetKind.rubric,
        AssetKind.prompt,
        AssetKind.skill,
        AssetKind.agent,
        AssetKind.settings,
      });
      expect(block.stationOverlayMappings, {'claude': '.claude'});
    });

    test('audience and selector are honoured INDEPENDENTLY', () {
      final assetAuthor = GridAssetsPack.assets.firstWhere(
        (a) => a.assetKey.id == 'asset-author',
      );
      expect(assetAuthor.audience, AssetAudience.human);
      expect(
        assetAuthor.selector,
        isA<RequiresPackage>().having(
          (s) => s.packageName,
          'packageName',
          'grid_sdk',
        ),
      );
      final decisionAlignment = GridAssetsPack.assets.firstWhere(
        (a) => a.assetKey.id == 'decision-alignment',
      );
      expect(decisionAlignment.audience, AssetAudience.agent);
      expect(
        decisionAlignment.selector,
        isA<RequiresPath>().having(
          (s) => s.relativePath,
          'relativePath',
          'docs/decisions',
        ),
      );
    });

    test('the pack validates and both legs of every skill are keyed', () {
      expect(GridAssetsPack.definition.assets, hasLength(28));
      final discover = GridAssetsPack.assets.firstWhere(
        (a) => a.assetKey.id == 'discover',
      );
      expect(discover.artifactKeys.map((k) => k.canonical), [
        'grid_assets/skill/discover@claude',
        'grid_assets/skill/discover@agents',
      ]);
    });
  });

  group('emission is ATOMIC and --check is honest', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('grid-block-');
      final source = _packageRoot();
      for (final relative in const [
        kGeneratedPackPath,
        kGeneratedMcpPath,
        _skillPath,
      ]) {
        final target = File(p.join(temp.path, relative));
        target.parent.createSync(recursive: true);
        if (relative == _skillPath) {
          target.writeAsStringSync('body\n');
        } else {
          target.writeAsStringSync(
            File(p.join(source, relative)).readAsStringSync(),
          );
        }
      }
    });

    tearDown(() => temp.deleteSync(recursive: true));

    void writePubspec(String assets) => File(
      p.join(temp.path, 'pubspec.yaml'),
    ).writeAsStringSync(_pubspec(assets));

    test('a malformed block leaves BOTH outputs byte-unchanged', () {
      final before = <String, String>{
        for (final relative in const [kGeneratedPackPath, kGeneratedMcpPath])
          relative: File(p.join(temp.path, relative)).readAsStringSync(),
      };
      writePubspec(
        '    - id: probe\n'
        '      kind: widget\n'
        '      description: "A probe."\n'
        '      artifacts:\n'
        '        - target: claude\n'
        '          path: $_skillPath\n',
      );
      expect(
        () =>
            runGridAssetsGenerator(packageRoot: temp.path, out: StringBuffer()),
        throwsA(isA<GridBlockException>()),
      );
      before.forEach((relative, text) {
        expect(File(p.join(temp.path, relative)).readAsStringSync(), text);
      });
    });

    test(
      '--check exits non-zero and names the stale path, writing nothing',
      () {
        writePubspec(_skill());
        final out = StringBuffer();
        expect(
          runGridAssetsGenerator(packageRoot: temp.path, check: true, out: out),
          isNot(0),
        );
        expect(out.toString(), contains('STALE $kGeneratedPackPath'));
        expect(out.toString(), contains('STALE $kGeneratedMcpPath'));
        expect(
          File(p.join(temp.path, kGeneratedPackPath)).readAsStringSync(),
          contains('code-validation'),
          reason: '--check writes nothing',
        );
      },
    );

    test('a write makes --check clean, and re-running is a no-op', () {
      writePubspec(_skill());
      expect(
        runGridAssetsGenerator(packageRoot: temp.path, out: StringBuffer()),
        0,
      );
      expect(
        runGridAssetsGenerator(
          packageRoot: temp.path,
          check: true,
          out: StringBuffer(),
        ),
        0,
      );
      expect(
        File(p.join(temp.path, kGeneratedPackPath)).readAsStringSync(),
        contains(kGridBlockGeneratedMarker),
      );
    });
  });
}
