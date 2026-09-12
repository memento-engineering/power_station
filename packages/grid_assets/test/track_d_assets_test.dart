// Track D — the Packaged-AI-Assets loader (M5 "The Circuit" / D-9).
//
// The committee's rubric prose + critic prompt template ship on disk in the
// Dart/Flutter "Packaged AI Assets" format (`extension/mcp/config.yaml` +
// `extension/rubrics/*.md` + `extension/prompts/critic.md`). This proves the
// [PackagedAssetLoader] reads them faithfully: every committee rubric loads to
// non-empty prose that names itself, an unknown rubric fails loud, the critic
// prompt renders with no leftover mustache holes, and the manifest declares the
// same four rubrics + the critic prompt (parsed as REAL yaml, not string-matched).
//
// Offline only — reads bundled files from a temp-free `extension/` dir. The
// manifest tests pin an explicit root off the shared package-root anchor; a
// separate group proves the loader ALSO resolves `extension/` via the package
// config from a foreign working directory (the repo-split fix). No live
// anything.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/asset_fakes.dart';
import 'support/package_root.dart';

/// The child executable that resolves the loader with no explicit root.
const String _probe = 'asset_loader_cwd_probe.dart';

void main() {
  // The explicit loader root, and the dir the manifest is read from, are the
  // SAME cwd-independent answer — so the two can never disagree on where the
  // assets are.
  final root = p.join(packageRoot(), 'extension');
  final loader = PackagedAssetLoader(root: root);

  group('PackagedAssetLoader — the committee rubrics', () {
    // BOTH committees' packs ride the one loader (bead `pow-6ao`): the code
    // rubrics + the spec-readiness rubrics resolve by id from the same
    // `extension/rubrics/`.
    for (final rubricId in [
      kGatingRubric,
      ...kLlmRubrics,
      ...kSpecCommitteeRubrics,
    ]) {
      test(
        'loadRubric("$rubricId") returns non-empty prose that names itself',
        () {
          final text = loader.loadRubric(rubricId);
          expect(text, isNotEmpty);
          // The rubric's own heading names it — a mis-wired path that loaded the
          // wrong file would not contain the lane's id.
          expect(text, contains(rubricId));
        },
      );
    }

    test(
      'an unknown rubric throws (fail-loud — a packaging bug, never a silent '
      'empty prompt)',
      () {
        expect(() => loader.loadRubric('does-not-exist'), throwsArgumentError);
      },
    );
  });

  group(
    'PackagedAssetLoader — cwd-independent resolution (the repo-split fix)',
    () {
      test('resolves rubrics from a foreign working directory — via the '
          'package config, since no cwd walk-up from there can ever reach the '
          'assets (the post-split space_station runner)', () async {
        // A dir that shares no ancestry with power_station's checkout: the cwd
        // walk-up is guaranteed to miss, so a passing load PROVES the package
        // config resolved it (not an accidental walk-up hit).
        //
        // Run as a CHILD process, never by assigning `Directory.current`: that
        // property is process-global and `dart test` runs suites concurrently,
        // so proving cwd-independence here by moving the cwd raced every
        // sibling suite's source reads.
        final foreign = await Directory.systemTemp.createTemp(
          'grid_assets_foreign_cwd_',
        );
        addTearDown(() => foreign.delete(recursive: true));

        final result = await Process.run(Platform.resolvedExecutable, <String>[
          p.join(packageRoot(), 'test', 'fixtures', _probe),
        ], workingDirectory: foreign.path);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stderr, isEmpty);
        // Not merely "something loaded": the loader resolved the SAME
        // `extension/` the explicit-root group reads its manifest from.
        expect(result.stdout, root);
      });
    },
  );

  group('PackagedAssetLoader — renderCriticPrompt', () {
    test('substitutes every hole (no `{{` survives) and embeds the bead + the '
        'rubric bands', () {
      final review = bead('tg-1').copyWith(
        title: 'Wire the federation bus',
        description: 'Connect The Studio to The Dashboard.',
      );
      final prompt = loader.renderCriticPrompt('spec-adherence', review);

      // No mustache hole leaked through (a missing var would print `{{...}}`).
      expect(prompt, isNot(contains('{{')));
      // The lane it grades.
      expect(prompt, contains('spec-adherence'));
      // The full work bead under review (the load-bearing review input).
      expect(prompt, contains('tg-1'));
      expect(prompt, contains('Wire the federation bus'));
      expect(prompt, contains('Connect The Studio to The Dashboard.'));
      // The rubric bands themselves — the `{{rubricText}}` substitution carried
      // the loaded prose, not a placeholder.
      expect(prompt, contains('Bands'));
      expect(prompt, contains(loader.loadRubric('spec-adherence')));
    });
  });

  group('extension/mcp/config.yaml — the Packaged-AI-Assets manifest', () {
    final manifest = File(p.join(root, 'mcp', 'config.yaml'));

    test('exists', () {
      expect(manifest.existsSync(), isTrue, reason: 'the manifest must ship');
    });

    test('declares all four rubric resources + the critic prompt, each with a '
        'visibility (parsed as real yaml)', () {
      final doc = loadYaml(manifest.readAsStringSync()) as YamlMap;

      // Resources: one per committee lane, each with id + visibility.
      final resources = (doc['resources'] as YamlList).cast<YamlMap>();
      final resourceIds = {for (final r in resources) r['id'] as String};
      expect(
        resourceIds,
        containsAll([kGatingRubric, ...kLlmRubrics, ...kSpecCommitteeRubrics]),
        reason:
            'every committee rubric — code AND spec-readiness — is '
            'declared as a resource',
      );
      for (final r in resources) {
        expect(
          r['visibility'],
          isNotNull,
          reason: 'resource ${r['id']} declares a visibility',
        );
      }

      // Prompts: the single `critic` prompt, with a visibility.
      final prompts = (doc['prompts'] as YamlList).cast<YamlMap>();
      final critic = prompts.firstWhere(
        (pr) => pr['id'] == 'critic',
        orElse: () => fail('the `critic` prompt must be declared'),
      );
      expect(
        critic['visibility'],
        isNotNull,
        reason: 'the critic prompt declares a visibility',
      );
    });
  });
}
