// The ONE bounded-output selector both packs render through, and the fence
// that keeps it one.
//
// The implementation lives in `dart_grid_assets` — the package this one
// already depends on — and the library of the same name here re-exports it, so
// the probes below exercise it through exactly the import every grid verb
// uses.
//
// Pure end to end: the selector takes renderers and a trim callback, so every
// probe is a value in and a value out — no process, no store, no disk except
// the source fence, which reads BOTH packs' `lib/` off the shared
// cwd-independent package root and its workspace sibling.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';

/// A trim policy under test: a value is just the text it renders to, and the
/// budget is how many of its characters survive.
///
/// The callback RECORDS every budget it was handed, so a probe can prove the
/// selector never trimmed at all rather than trimming to the whole value.
final class _Policy {
  _Policy(this.complete, {this.jsonPrefix = ''});

  /// The untrimmed text.
  final String complete;

  /// Text the JSON rendering pays that the plain one does not — how a probe
  /// makes the JSON the BINDING rendering.
  final String jsonPrefix;

  /// Every budget [at] was called with, in order.
  final List<int> budgets = [];

  int get maximumBudget => complete.length;

  /// The marker every cut candidate carries — the selector's contract is that
  /// a policy NAMES what it withheld, so the floor is the marker alone and
  /// every larger candidate is the marker plus content. Monotone by
  /// construction.
  static const String marker = '[withheld]';

  String at(int budget) {
    budgets.add(budget);
    if (budget <= 0) return marker;
    return complete.substring(0, budget.clamp(0, complete.length)) + marker;
  }

  String select() => boundedOutput<String>(
    complete: complete,
    maximumTrimBudget: maximumBudget,
    renderPlain: (value) => value,
    renderJson: (value) => '$jsonPrefix$value',
    trim: at,
  );
}

/// A string of exactly [bytes] single-byte characters.
String _ascii(int bytes) => 'x' * bytes;

void main() {
  group('the selector', () {
    test('a complete value that fits comes back UNTOUCHED, untrimmed', () {
      final policy = _Policy(_ascii(kBoundedOutputCapBytes - 1));

      expect(policy.select(), policy.complete);
      expect(
        policy.budgets,
        isEmpty,
        reason: 'a value that fits is never handed to the policy at all',
      );
    });

    test('the trailing newline is counted, so the cap is the LAST byte', () {
      // The command writes `value\n`, so a rendering of cap-1 bytes is exactly
      // the cap and one more byte is over it.
      expect(
        _Policy(_ascii(kBoundedOutputCapBytes - 1)).select().length,
        kBoundedOutputCapBytes - 1,
      );
      expect(
        _Policy(_ascii(kBoundedOutputCapBytes)).select().length,
        lessThan(kBoundedOutputCapBytes),
      );
    });

    test('the largest fitting budget wins', () {
      final policy = _Policy(_ascii(kBoundedOutputCapBytes * 3));

      final selected = policy.select();

      // cap-1 characters plus the newline is exactly the cap.
      expect(selected.length, kBoundedOutputCapBytes - 1);
      expect(selected, endsWith(_Policy.marker));
      expect(
        policy.complete.startsWith(
          selected.substring(0, selected.length - _Policy.marker.length),
        ),
        isTrue,
      );
    });

    test('the JSON rendering can be the BINDING one', () {
      // Plain fits with room to spare; the JSON rendering of the same value
      // does not, and a bound that measured only the plain text would ship an
      // over-cap structured result.
      final policy = _Policy(
        _ascii(kBoundedOutputCapBytes - 100),
        jsonPrefix: _ascii(500),
      );

      final selected = policy.select();

      expect(selected.length, kBoundedOutputCapBytes - 501);
      expect(
        utf8.encode(selected).length + 1,
        lessThan(kBoundedOutputCapBytes),
      );
    });

    test('the zero-budget fallback is the floor, and it carries the '
        'marker', () {
      // Nothing but the fallback fits: one character of content already puts
      // the JSON rendering over.
      final policy = _Policy(
        _ascii(kBoundedOutputCapBytes * 2),
        jsonPrefix: _ascii(kBoundedOutputCapBytes - _Policy.marker.length - 1),
      );

      final selected = policy.select();

      expect(selected, _Policy.marker);
      expect(policy.budgets, contains(0));
    });

    test('a zero-budget fallback over the cap REFUSES loudly', () {
      // A policy whose smallest candidate is itself over the cap has no
      // bounded answer; emitting the unbounded one anyway is the silent
      // truncation the ratified entry calls worse than no cap.
      expect(
        () => boundedOutput<String>(
          complete: _ascii(kBoundedOutputCapBytes * 2),
          maximumTrimBudget: 10,
          renderPlain: (value) => value,
          renderJson: (value) => value,
          trim: (_) => _ascii(kBoundedOutputCapBytes * 2),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('no bounded rendering'),
              contains('$kBoundedOutputCapBytes'),
            ),
          ),
        ),
      );
    });

    test('a negative budget is a caller bug, and it is LOUD', () {
      expect(
        () => boundedOutput<String>(
          complete: _ascii(kBoundedOutputCapBytes * 2),
          maximumTrimBudget: -1,
          renderPlain: (value) => value,
          renderJson: (value) => value,
          trim: (_) => '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('renderedBytes counts UTF-8 plus the one newline', () {
      expect(renderedBytes(''), 1);
      expect(renderedBytes('abc'), 4);
      expect(renderedBytes('日本語'), 10);
    });
  });

  group('AC-9 — the bound is the PACKS\', not a verb\'s', () {
    test('one shared cap and dual-render search', () {
      final sources = _libSources();

      // ONE cap value across BOTH packs, and it is the shared one.
      final capDeclarations = {
        for (final entry in sources.entries)
          if (_capDeclaration.hasMatch(entry.value))
            entry.key: _capDeclaration
                .allMatches(entry.value)
                .map((match) => match.group(1)!)
                .toList(),
      };
      expect(capDeclarations, {
        _implementation: ['kBoundedOutputCapBytes'],
      });

      // No verb keeps a bound of its own: not `prime`, which arrived second,
      // and not the `dart release ladder` that arrived third with a private
      // cap and a private reservation arithmetic.
      for (final entry in sources.entries) {
        for (final minted in const [
          'kPrimeOutputCapBytes',
          'kLadderOutputCapBytes',
          '_reservedBytes',
        ]) {
          expect(
            entry.value,
            isNot(contains(minted)),
            reason: '${entry.key} keeps the per-command bound $minted alive',
          );
        }
      }

      // The retired per-verb cap name survives ONLY as the deprecated alias.
      for (final entry in sources.entries) {
        for (final line in const LineSplitter().convert(entry.value)) {
          if (!line.contains('kShowOutputCapBytes')) continue;
          expect(
            line,
            'const int kShowOutputCapBytes = kBoundedOutputCapBytes;',
            reason: '${entry.key} names the retired cap outside its alias',
          );
        }
      }

      // The dual-render FIT PREDICATE lives in one file. Everywhere else the
      // cap may only be reported, never compared against.
      for (final entry in sources.entries) {
        if (entry.key == _implementation) continue;
        expect(
          _collapsed(entry.value),
          isNot(contains('<= kBoundedOutputCapBytes')),
          reason: '${entry.key} re-implements the fit predicate',
        );
      }

      // The outcome-budget SEARCH lives in one file too. The second `low <=
      // high` in either pack is `_ProseChunk.cutTo`, show's rune-prefix cut —
      // policy, not candidate selection — and it is named here so a third one
      // cannot arrive unnoticed.
      expect(
        {
          for (final entry in sources.entries)
            if (_collapsed(entry.value).contains('while (low <= high)'))
              entry.key: 'while (low <= high)'
                  .allMatches(_collapsed(entry.value))
                  .length,
        },
        {
          _implementation: 1,
          p.join('grid_assets', 'src', 'filing', 'show_command.dart'): 1,
        },
      );

      // Each consumer CALLS the selector, exactly once — and the consumers are
      // exactly the three verbs that bound their output, across both packs.
      expect(
        {
          for (final entry in sources.entries)
            if (entry.value.contains('boundedOutput<'))
              entry.key: 'boundedOutput<'.allMatches(entry.value).length,
        },
        {
          _implementation: 1,
          p.join('dart_grid_assets', 'src', 'dart', 'release_service.dart'): 1,
          p.join('grid_assets', 'src', 'filing', 'show_command.dart'): 1,
          p.join('grid_assets', 'src', 'seat', 'prime_command.dart'): 1,
        },
      );
      expect(
        sources[p.join(
          'dart_grid_assets',
          'src',
          'dart',
          'release_service.dart',
        )],
        contains('boundedOutput<ReleaseLadderReport>('),
        reason: 'the ladder SELECTS a window rather than searching for one',
      );

      // The library at the old grid path is EXPORT-ONLY: a compatibility
      // surface for the verbs and the barrel that already import it, holding
      // no cap, no predicate and no search of its own.
      expect(
        _code(sources[_shim]!),
        'library; '
        "export 'package:dart_grid_assets/dart_grid_assets.dart' "
        'show boundedOutput, kBoundedOutputCapBytes, renderedBytes;',
      );
    });
  });
}

/// The one implementation's key in [_libSources].
final String _implementation = p.join(
  'dart_grid_assets',
  'src',
  'io',
  'bounded_output.dart',
);

/// The grid re-export's key in [_libSources] — the path every grid verb and
/// `grid_assets.dart` still import.
final String _shim = p.join('grid_assets', 'src', 'io', 'bounded_output.dart');

/// The declaration of an output-cap constant, whatever it is named.
final RegExp _capDeclaration = RegExp(
  r'^const int (\w+) = 8000;$',
  multiLine: true,
);

/// [source] with every whitespace run collapsed to one space, so a probe reads
/// the same after `dart format` re-wraps a signature.
String _collapsed(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

/// [source] with its comments and blank lines dropped and what is left joined
/// into one line — the CODE a library declares, whatever the prose above it
/// says.
String _code(String source) => const LineSplitter()
    .convert(source)
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty && !line.startsWith('//'))
    .join(' ');

/// Every Dart source under BOTH packs' `lib/`, keyed by
/// `<package>/<lib-relative path>`.
///
/// Both trees, because the bound is now one implementation ACROSS a dependency
/// edge: it lives in `dart_grid_assets` and this pack re-exports it. A fence
/// that read only this package's `lib/` could not see the implementation it
/// fences, nor the third consumer that made the move necessary, and would go on
/// passing while a second copy grew next door.
Map<String, String> _libSources() => {
  ..._packSources('grid_assets', packageRoot()),
  ..._packSources('dart_grid_assets', _siblingPackageRoot('dart_grid_assets')),
};

/// Every Dart source under [root]'s `lib/`, keyed by `<package>/<relative>`.
/// LOUD when it finds none — a source fence that silently reads nothing is a
/// fence that is GONE.
Map<String, String> _packSources(String package, String root) {
  final lib = Directory(p.join(root, 'lib'));
  final sources = <String, String>{
    for (final entity in lib.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart'))
        p.join(package, p.relative(entity.path, from: lib.path)): entity
            .readAsStringSync(),
  };
  if (sources.isEmpty) fail('no Dart sources under ${lib.path}');
  return sources;
}

/// The workspace sibling named [package], resolved off this package's OWN
/// source-located root — never off the process working directory, which is a
/// shared mutable global under `dart test`.
///
/// LOUD when nothing there declares [package]: a fence that quietly skipped the
/// tree holding the implementation is a fence that is GONE.
String _siblingPackageRoot(String package) {
  final root = p.join(p.dirname(packageRoot()), package);
  final pubspec = File(p.join(root, 'pubspec.yaml'));
  final declaresPackage = RegExp('^name:\\s*$package\\s*\$');
  if (!pubspec.existsSync() ||
      !pubspec.readAsLinesSync().any(declaresPackage.hasMatch)) {
    fail('no pubspec.yaml naming $package at $root');
  }
  return root;
}
