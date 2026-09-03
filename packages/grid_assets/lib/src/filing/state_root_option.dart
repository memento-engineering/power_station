import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// The ONE `--state-root` option name both filing verbs expose.
const String kStateRootOption = 'state-root';

/// The ONE help line both verbs print for [kStateRootOption].
const String kStateRootHelp =
    'The grid home whose .grid/.beads holds the cross-store link beads.';

/// The default injected state root: NONE. Until a station threads its grid
/// home in, only local `blocks` edges count as wiring.
String? noStateRoot() => null;

/// Registers [kStateRootOption] on [parser] — the seam both verbs ride so the
/// option name and its help cannot drift apart between them.
void addStateRootOption(ArgParser parser) =>
    parser.addOption(kStateRootOption, help: kStateRootHelp);

/// Resolves the state root for one run: the parsed [kStateRootOption] when it
/// carries a non-blank path, else the station-injected [fallback].
String? resolveStateRoot(ArgResults results, String? Function() fallback) {
  final option = results.option(kStateRootOption)?.trim();
  return option == null || option.isEmpty ? fallback() : p.normalize(option);
}
