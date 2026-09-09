import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

WorkflowRunIntakeRule _rule({
  String workflowPath = '.github/workflows/ci.yaml',
  String validationPlan = 'dart test',
  Set<String>? events,
  Set<String>? branches,
  Set<String>? conclusions,
  int priority = 1,
  bool approve = true,
}) => WorkflowRunIntakeRule(
  workflowPath: workflowPath,
  validationPlan: validationPlan,
  events: events ?? kDefaultWorkflowRunEvents,
  branches: branches,
  conclusions: conclusions ?? kDefaultWorkflowRunConclusions,
  priority: priority,
  approve: approve,
);

bool _matches(
  WorkflowRunIntakeRule rule, {
  String workflowPath = '.github/workflows/ci.yaml',
  String event = 'schedule',
  String headBranch = 'main',
  String conclusion = 'failure',
  String defaultBranch = 'main',
}) => rule.matches(
  workflowPath: workflowPath,
  event: event,
  headBranch: headBranch,
  conclusion: conclusion,
  defaultBranch: defaultBranch,
);

void main() {
  group('WorkflowRunIntakeRule defaults', () {
    test('admit the three non-fork triggers and the two bad endings', () {
      final rule = _rule();
      expect(rule.events, {'schedule', 'push', 'workflow_dispatch'});
      expect(rule.conclusions, {'failure', 'timed_out'});
      expect(rule.priority, 1);
      expect(rule.approve, isTrue);
      expect(
        rule.events,
        isNot(contains('pull_request')),
        reason: 'a fork PR run must never be admitted by default',
      );
    });

    test('an omitted branch set resolves to the seat default branch', () {
      final rule = _rule();
      expect(rule.branches, isNull);
      expect(rule.effectiveBranches('m3-runtime'), {'m3-runtime'});
      expect(_matches(rule, headBranch: 'main'), isTrue);
      expect(
        _matches(rule, headBranch: 'release', defaultBranch: 'release'),
        isTrue,
      );
      expect(_matches(rule, headBranch: 'topic'), isFalse);
    });

    test('a declared branch set is matched exactly, ignoring the default', () {
      final rule = _rule(branches: {'release'});
      expect(rule.effectiveBranches('main'), {'release'});
      expect(_matches(rule, headBranch: 'release'), isTrue);
      expect(_matches(rule, headBranch: 'main'), isFalse);
    });

    test('every declared criterion is required', () {
      final rule = _rule();
      expect(_matches(rule), isTrue);
      expect(_matches(rule, workflowPath: 'ci.yaml'), isFalse);
      expect(_matches(rule, event: 'pull_request'), isFalse);
      expect(_matches(rule, conclusion: 'success'), isFalse);
      expect(_matches(rule, conclusion: 'timed_out'), isTrue);
    });

    test('the sets are immutable once declared', () {
      final rule = _rule();
      expect(() => rule.events.add('pull_request'), throwsUnsupportedError);
      expect(() => rule.conclusions.add('success'), throwsUnsupportedError);
    });
  });

  group('WorkflowRunIntakeRule refuses loudly', () {
    test('a blank workflow path', () {
      expect(() => _rule(workflowPath: '  '), throwsArgumentError);
    });

    test('an empty selector that could never match', () {
      expect(() => _rule(events: const {}), throwsArgumentError);
      expect(() => _rule(conclusions: const {}), throwsArgumentError);
      expect(() => _rule(branches: const {}), throwsArgumentError);
    });

    test('a priority outside 0 through 4', () {
      for (final priority in [-1, 5]) {
        expect(() => _rule(priority: priority), throwsArgumentError);
      }
      for (final priority in [0, 4]) {
        expect(_rule(priority: priority).priority, priority);
      }
    });

    test('but never a blank validation plan — the preflight owns that', () {
      final rule = _rule(validationPlan: '');
      expect(rule.validationPlan, isEmpty);
      expect(_matches(rule), isTrue);
    });
  });

  group('matchWorkflowRunRule', () {
    test('returns the FIRST declared match, not the narrowest', () {
      final first = _rule(priority: 1, validationPlan: 'first');
      final second = _rule(priority: 0, validationPlan: 'second');
      final selected = matchWorkflowRunRule(
        [first, second],
        workflowPath: '.github/workflows/ci.yaml',
        event: 'schedule',
        headBranch: 'main',
        conclusion: 'failure',
        defaultBranch: 'main',
      );
      expect(selected, same(first));
    });

    test('skips non-matching rules and returns null when none match', () {
      final release = _rule(workflowPath: '.github/workflows/release.yaml');
      final ci = _rule();
      expect(
        matchWorkflowRunRule(
          [release, ci],
          workflowPath: '.github/workflows/ci.yaml',
          event: 'schedule',
          headBranch: 'main',
          conclusion: 'failure',
          defaultBranch: 'main',
        ),
        same(ci),
      );
      expect(
        matchWorkflowRunRule(
          [release, ci],
          workflowPath: '.github/workflows/ci.yaml',
          event: 'schedule',
          headBranch: 'main',
          conclusion: 'success',
          defaultBranch: 'main',
        ),
        isNull,
      );
      expect(
        matchWorkflowRunRule(
          const <WorkflowRunIntakeRule>[],
          workflowPath: '.github/workflows/ci.yaml',
          event: 'schedule',
          headBranch: 'main',
          conclusion: 'failure',
          defaultBranch: 'main',
        ),
        isNull,
      );
    });
  });
}
