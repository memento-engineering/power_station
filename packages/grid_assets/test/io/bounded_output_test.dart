// The pack's ONE bounded-output selector, and the fence that keeps it one.
//
// Pure end to end: the selector takes renderers and a trim callback, so every
// probe below is a value in and a value out — no process, no store, no disk
// except the source fence, which reads this package's own `lib/` off the
// shared cwd-independent package root.
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

  group('AC-9 — the bound is the PACK\'s, not a verb\'s', () {
    test('one shared cap and dual-render search', () {
      final sources = _libSources();

      // ONE cap value in the whole package, and it is the shared one.
      final capDeclarations = {
        for (final entry in sources.entries)
          if (_capDeclaration.hasMatch(entry.value))
            entry.key: _capDeclaration
                .allMatches(entry.value)
                .map((match) => match.group(1)!)
                .toList(),
      };
      expect(capDeclarations, {
        p.join('src', 'io', 'bounded_output.dart'): ['kBoundedOutputCapBytes'],
      });

      // The verb that arrived second never minted a cap of its own.
      for (final entry in sources.entries) {
        expect(
          entry.value,
          isNot(contains('kPrimeOutputCapBytes')),
          reason: '${entry.key} mints a third per-command cap',
        );
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
        if (entry.key == p.join('src', 'io', 'bounded_output.dart')) continue;
        expect(
          _collapsed(entry.value),
          isNot(contains('<= kBoundedOutputCapBytes')),
          reason: '${entry.key} re-implements the fit predicate',
        );
      }

      // The outcome-budget SEARCH lives in one file too. The second `low <=
      // high` in the package is `_ProseChunk.cutTo`, show's rune-prefix cut —
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
          p.join('src', 'io', 'bounded_output.dart'): 1,
          p.join('src', 'filing', 'show_command.dart'): 1,
        },
      );

      // Each consumer CALLS the selector, exactly once — and the consumers are
      // exactly the two verbs that bound their output.
      expect(
        {
          for (final entry in sources.entries)
            if (entry.value.contains('boundedOutput<'))
              entry.key: 'boundedOutput<'.allMatches(entry.value).length,
        },
        {
          p.join('src', 'io', 'bounded_output.dart'): 1,
          p.join('src', 'filing', 'show_command.dart'): 1,
          p.join('src', 'seat', 'prime_command.dart'): 1,
        },
      );
    });
  });
}

/// The declaration of an output-cap constant, whatever it is named.
final RegExp _capDeclaration = RegExp(
  r'^const int (\w+) = 8000;$',
  multiLine: true,
);

/// [source] with every whitespace run collapsed to one space, so a probe reads
/// the same after `dart format` re-wraps a signature.
String _collapsed(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

/// Every Dart source under this package's `lib/`, keyed by its `lib`-relative
/// path. LOUD when it finds none — a source fence that silently reads nothing
/// is a fence that is GONE.
Map<String, String> _libSources() {
  final lib = Directory(p.join(packageRoot(), 'lib'));
  final sources = <String, String>{
    for (final entity in lib.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart'))
        p.relative(entity.path, from: lib.path): entity.readAsStringSync(),
  };
  if (sources.isEmpty) fail('no Dart sources under ${lib.path}');
  return sources;
}
