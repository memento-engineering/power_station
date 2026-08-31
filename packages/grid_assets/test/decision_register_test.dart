import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _writeDecision(Directory root, String relativePath, String body) {
  final file = File(p.join(root.path, relativePath));
  file.createSync(recursive: true);
  file.writeAsStringSync(body);
  return relativePath;
}

List<String> _run(Directory root, String command) {
  final result = Process.runSync('sh', [
    '-c',
    command,
  ], workingDirectory: root.path);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return result.stdout
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('decision-register-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('docs/decisions-only surfaces its decision and quoted clause', () {
    const quote =
        'admission and durable transitions consult one owned authority';
    final decision = _writeDecision(
      root,
      'docs/decisions/2026-08-30-admission-authority-boundary.md',
      '# Admission authority boundary\n\n$quote\n',
    );

    expect(_run(root, localDecisionRegisterListCommand()), [decision]);
    expect(_run(root, localDecisionRegisterGrepCommand('owned authority')), [
      decision,
    ]);
    expect(
      File(p.join(root.path, decision)).readAsStringSync(),
      contains(quote),
    );
  });

  test('docs/adr-only preserves the legacy result', () {
    const quote = 'one verdict transport stack';
    final decision = _writeDecision(
      root,
      'docs/adr/ADR-0001-verdict-transport.md',
      '# ADR-0001\n\n$quote\n',
    );

    expect(_run(root, localDecisionRegisterListCommand()), [decision]);
    expect(_run(root, localDecisionRegisterGrepCommand('verdict transport')), [
      decision,
    ]);
    expect(
      File(p.join(root.path, decision)).readAsStringSync(),
      contains(quote),
    );
  });

  test('both registers surface both entries', () {
    final adr = _writeDecision(
      root,
      'docs/adr/ADR-0001-legacy.md',
      '# Legacy\n\nshared-register-token\n',
    );
    final decision = _writeDecision(
      root,
      'docs/decisions/2026-08-30-modern.md',
      '# Modern\n\nshared-register-token\n',
    );

    expect(_run(root, localDecisionRegisterListCommand()), [adr, decision]);
    expect(
      _run(root, localDecisionRegisterGrepCommand('shared-register-token')),
      [adr, decision],
    );
  });

  test('neither register is an empty successful result', () {
    expect(_run(root, localDecisionRegisterListCommand()), isEmpty);
    expect(_run(root, localDecisionRegisterGrepCommand('authority')), isEmpty);
  });

  test('slug-form citation round-trips as a gateable decision', () {
    final finding = DiscoveryFinding.fromJson({
      'kind': 'decision',
      'standard': 'the_grid#admission-authority-boundary',
      'quote': 'admission and durable transitions consult one owned authority',
      'contradiction': 'the bead introduces a second admission authority',
      'contradicts': true,
      'acknowledged': false,
      'ratified': true,
      'removesOffence': false,
      'precedent': '',
    });

    expect(finding, isNotNull);
    expect(finding!.standard, 'the_grid#admission-authority-boundary');
    expect(finding.toJson()['standard'], finding.standard);
    expect(gatesTheBead(finding), isTrue);
  });
}
