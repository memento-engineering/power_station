import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// The ONE `--state-root` option name the verbs that REACH the grid home's
/// state store expose — `park`, `show` and `mount`.
///
/// `mount` is the THIRD consumer and rides this seam rather than declaring an
/// option of its own: its `session_occupancy`, `verdict_cap` and
/// `mount_attempt_cap` rows are projections of the session-lifecycle, step and
/// mount-attempt beads the grid home holds, which is exactly the store this
/// option names.
const String kStateRootOption = 'state-root';

/// The ONE help line every verb prints for [kStateRootOption].
///
/// It names the GRID HOME rather than a store because that home is where the
/// state beads live — the SESSION-LIFECYCLE beads `park` closes and retires,
/// and the root `show` validates against. One home, one option, one
/// resolution.
///
/// `filing`, `approve` and `unpark` no longer take it at all: their
/// dependencies row is a projection of the WORK store's own bd rows and
/// reaches no second store (Nico, 2026-09-13, under
/// `the_grid#the-grid-is-a-beads-controller`). A verb that accepted a root it
/// never reads teaches an operator that the root matters to its answer.
const String kStateRootHelp =
    'The grid home whose .grid/.beads holds the session-lifecycle state beads.';

/// The state-store directory a grid home holds — the child [resolveStateRoot]
/// appends so the documented grid home reaches the state beads.
const String _stateStoreDir = '.grid';

/// The bd workspace directory a state store holds — how [resolveStateRoot]
/// recognizes a path that is ALREADY the state store.
const String _beadsDir = '.beads';

/// The default injected state root: NONE. The verb that REQUIRES the home
/// (`park`) refuses rather than guess at one.
String? noStateRoot() => null;

/// Registers [kStateRootOption] on [parser] — the seam every verb rides so the
/// option name and its help cannot drift apart between them.
void addStateRootOption(ArgParser parser) =>
    parser.addOption(kStateRootOption, help: kStateRootHelp);

/// Resolves the state root for one run: the parsed [kStateRootOption] when it
/// carries a non-blank path, else the station-injected [fallback]. Null when
/// neither names one — the state store is then NOT consulted.
///
/// The public contract is the GRID HOME, exactly as [kStateRootHelp] says and
/// exactly as `--grid-home` takes it everywhere else on the runner, so a
/// selected root that holds a `.grid` directory resolves to that child. A path
/// that is already the state store (it holds `.beads`) resolves to itself, and
/// a home holding both prefers `.grid`.
///
/// Guards LOUD or GONE (the D-H doctrine, ADR-0008): a root holding neither
/// child is REFUSED by [StateError] naming the root and both expected
/// children, because a verb that silently accepted an unrelated root would
/// report it as fine.
String? resolveStateRoot(ArgResults results, String? Function() fallback) {
  final option = results.option(kStateRootOption)?.trim();
  final selected = option == null || option.isEmpty
      ? fallback()?.trim()
      : option;
  if (selected == null || selected.isEmpty) return null;
  final root = p.normalize(selected);
  final store = p.join(root, _stateStoreDir);
  if (Directory(store).existsSync()) return store;
  if (Directory(p.join(root, _beadsDir)).existsSync()) return root;
  throw StateError(
    '--state-root "$root" is neither a grid home (no $_stateStoreDir '
    'directory) nor a state store (no $_beadsDir directory)',
  );
}
