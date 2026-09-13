/// The pack's bounded-output selector, re-exported from where it now lives.
///
/// The implementation moved DOWN into `dart_grid_assets` when `dart release
/// ladder` became the THIRD verb to need the same cap, fit predicate, budget
/// search and marker contract
/// (`power_station#a-mechanical-lookup-is-a-vended-command-with-a-bounded-output`:
/// the three properties a vended command owes its reader are "implemented once
/// in the CLI SDK"). `grid_assets` already depends on `dart_grid_assets`, so
/// homing the one implementation there puts it in reach of every verb in both
/// packs with no new dependency edge and never a reverse one
/// (`power_station#a2-the-grid-assets-dart-grid-assets-dependency-direction-was`).
///
/// This library is the COMPATIBILITY surface and nothing else: the grid verbs
/// and `grid_assets.dart` keep reaching the same three symbols at the same
/// path. It declares no cap, no predicate and no search of its own — a second
/// copy HERE is precisely the duplication the move retired.
///
/// Not to be confused with `BoundedTextBudget` of `code/describe_manifest.dart`:
/// that clamps ONE plain model-input stream at a line boundary and leaves the
/// omission prose to its caller. The selector re-exported here selects between
/// whole rendered candidates against BOTH of a command's renderings.
library;

export 'package:dart_grid_assets/dart_grid_assets.dart'
    show boundedOutput, kBoundedOutputCapBytes, renderedBytes;
