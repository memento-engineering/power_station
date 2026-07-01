/// The `code` asset's run command — a [StationRunCommand] configured with the
/// `code` trio (ADR-0008 D1 asset seam).
///
/// This is the reusable CLI component the CODE ASSET offers alongside its domain
/// components ([buildCodeRegistry] / [kCodeFormula]) — the CLI-SDK model: an
/// asset's offering = {domain components + CLI components}. It moved here from
/// `grid_cli` at the `power_station` repo split, over the extracted CLI-SDK
/// framework lib — the runner just `..addCommand(CodeRunCommand())`.
library;

import 'package:grid_cli/grid_cli.dart';
import 'package:grid_controller/grid_controller.dart' show Bead;
import 'package:grid_engine/grid_engine.dart';

import 'code_capabilities.dart';

/// The bead→formula policy for the `code` asset — all coding work roots the
/// `code` formula (agent → review → land). A top-level tear-off so
/// [FormulaResolver] stays const.
Formula _codeFormula(Bead bead) => kCodeFormula;

/// `grid run` for the `code` asset: the reentrant tree engine spawning a coding
/// agent per ready bead, wired with the `code` formula + [buildCodeRegistry] +
/// the git `SourceControl` (built from the live wiring via `servicesFor` — the
/// framework composer holds no git opinion; provisioning + land are THIS
/// asset's).
class CodeRunCommand extends StationRunCommand {
  /// Creates the code run command (the `code` trio into the de-opinionated base).
  CodeRunCommand()
    : super(
        resolver: const FormulaResolver(_codeFormula),
        registry: buildCodeRegistry(),
        servicesFor: _codeServices,
      );

  /// The code asset's per-substation services: a git [SourceControl] over the
  /// live worktree service + root (provisioning works even when LAND is off —
  /// gitOps/prOpener are non-null only when `--land` armed a live run; null ⇒
  /// `canLand` false ⇒ the land capability no-ops, the commit-only posture).
  static ServiceBundle _codeServices(AssetWiring wiring) => ServiceBundle(
    sourceControl: GitSourceControl(
      gitOps: wiring.gitOps,
      prOpener: wiring.prOpener,
      provisioner: wiring.git,
      root: wiring.workRoot,
    ),
  );

  @override
  final String name = 'run';

  @override
  final String description =
      'Run the CODE asset on the tree engine (tree-as-default): the reactive '
      'controller + the reentrant engine that spawns a coding agent per ready '
      'bead, over one shared ownership allow-set. Defaults to --dry-run '
      '(observe-only). Run under `dart run --enable-vm-service` so leonard can '
      'attach.';
}
