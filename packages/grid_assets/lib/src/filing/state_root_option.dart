import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// The ONE `--state-root` option name both filing verbs expose.
const String kStateRootOption = 'state-root';

/// The ONE help line both verbs print for [kStateRootOption].
const String kStateRootHelp =
    'The grid home whose .grid/.beads holds the cross-store link beads.';

/// The state-store directory a grid home holds — the child [resolveStateRoot]
/// appends so the documented grid home reaches the link beads.
const String _stateStoreDir = '.grid';

/// The bd workspace directory a state store holds — how [resolveStateRoot]
/// recognizes a path that is ALREADY the state store.
const String _beadsDir = '.beads';

/// The default injected state root: NONE. Until a station threads its grid
/// home in, only local `blocks` edges count as wiring.
String? noStateRoot() => null;

/// Registers [kStateRootOption] on [parser] — the seam both verbs ride so the
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
/// a home holding both prefers `.grid`. Passing the grid home used to reach bd
/// in the WORK store, where `list -t link` dies on `invalid issue type "link"`.
///
/// Guards LOUD or GONE (the D-H doctrine, ADR-0008): a root holding neither
/// child is REFUSED by [StateError] naming the root and both expected
/// children, because silently reading no link beads reports every wired
/// cross-store blocker as unwired.
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
