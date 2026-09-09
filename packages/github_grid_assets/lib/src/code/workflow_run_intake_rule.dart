library;

/// The `workflow_run` trigger events a rule admits when it declares none.
///
/// `pull_request` is deliberately ABSENT: a fork's pull-request run executes
/// contributor-authored workflow code, so admitting it by default would let an
/// external actor mint station work. A seat that wants it must say so.
const Set<String> kDefaultWorkflowRunEvents = <String>{
  'schedule',
  'push',
  'workflow_dispatch',
};

/// The completed-run conclusions a rule admits when it declares none.
const Set<String> kDefaultWorkflowRunConclusions = <String>{
  'failure',
  'timed_out',
};

/// One seat-declared criterion selecting which completed workflow runs become
/// station work.
///
/// A plain VALUE, modelled on the `GitHubDeliveryPolicy` beside it: it holds
/// no transport and reaches nothing, so a seat's whole workflow-run posture is
/// decidable — and testable — without a network.
///
/// An omitted [branches] resolves through [effectiveBranches] to the seat's
/// own default branch, because the failure this rule exists to catch is a red
/// run on the branch nobody is watching. A declared set is matched EXACTLY.
final class WorkflowRunIntakeRule {
  /// Declares one rule for [workflowPath], gated by [validationPlan].
  ///
  /// [validationPlan] may be blank; it is not refused here. A blank plan fails
  /// the filing preflight downstream, which leaves the filed bead OPEN and
  /// unstamped — the designed outcome, and a LOUDER one than a construction
  /// error a seat would only see at boot.
  WorkflowRunIntakeRule({
    required String workflowPath,
    required this.validationPlan,
    Set<String> events = kDefaultWorkflowRunEvents,
    Set<String>? branches,
    Set<String> conclusions = kDefaultWorkflowRunConclusions,
    this.priority = 1,
    this.approve = true,
  }) : workflowPath = workflowPath.trim().isEmpty
           ? throw ArgumentError.value(
               workflowPath,
               'workflowPath',
               'must not be blank',
             )
           : workflowPath,
       events = _declared(events, 'events'),
       branches = branches == null ? null : _declared(branches, 'branches'),
       conclusions = _declared(conclusions, 'conclusions') {
    if (priority < 0 || priority > 4) {
      throw ArgumentError.value(priority, 'priority', 'must be 0 through 4');
    }
  }

  /// An empty selector can never match, so a rule carrying one is a rule the
  /// seat believes is armed and is not. Refused LOUDLY at declaration.
  static Set<String> _declared(Set<String> values, String name) =>
      values.isEmpty
      ? throw ArgumentError.value(values, name, 'must declare a value')
      : Set<String>.unmodifiable(values);

  /// The repository-relative workflow file, e.g. `.github/workflows/ci.yaml`.
  final String workflowPath;

  /// The command an agent runs to falsify the failure this rule files.
  ///
  /// Written to the bead as `validation_plan`; the filing preflight refuses a
  /// blank one, so approval never rides a bead nobody can check.
  final String validationPlan;

  /// The trigger events admitted, e.g. `schedule`.
  final Set<String> events;

  /// The head branches admitted, or null for the seat's default branch.
  final Set<String>? branches;

  /// The completed-run conclusions admitted, e.g. `failure`.
  final Set<String> conclusions;

  /// Priority stamped on the filed bug.
  final int priority;

  /// Whether a SELF-authority match is approved as part of filing.
  final bool approve;

  /// The branches this rule admits at a seat whose default is [defaultBranch].
  Set<String> effectiveBranches(String defaultBranch) =>
      branches ?? <String>{defaultBranch};

  /// Whether one completed run satisfies every declared criterion.
  bool matches({
    required String workflowPath,
    required String event,
    required String headBranch,
    required String conclusion,
    required String defaultBranch,
  }) =>
      workflowPath == this.workflowPath &&
      events.contains(event) &&
      effectiveBranches(defaultBranch).contains(headBranch) &&
      conclusions.contains(conclusion);
}

/// The FIRST rule in [rules] that matches, or null when none does.
///
/// Declaration order is authoritative — a seat that declares two overlapping
/// rules gets the earlier one's priority, plan and approval posture, and never
/// two beads for one run. This is the ONE selector: the poll leg uses it to
/// decide whether a run is worth a jobs request, and the intake projection
/// uses it again to recover the rule that admitted the observation.
WorkflowRunIntakeRule? matchWorkflowRunRule(
  Iterable<WorkflowRunIntakeRule> rules, {
  required String workflowPath,
  required String event,
  required String headBranch,
  required String conclusion,
  required String defaultBranch,
}) {
  for (final rule in rules) {
    if (rule.matches(
      workflowPath: workflowPath,
      event: event,
      headBranch: headBranch,
      conclusion: conclusion,
      defaultBranch: defaultBranch,
    )) {
      return rule;
    }
  }
  return null;
}
