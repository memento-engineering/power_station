/// The DART domain grid assets — the typed `grid.dart` envelope + pub dev-time
/// linkage + the exported [DartCommand] (the CLI-SDK model: a domain asset
/// offers domain components AND CLI components; a station runner just
/// `..addCommand(DartCommand())`).
///
/// Carved out of `grid_assets` at the `power_station` repo split (see the_grid
/// `docs/SCRATCH-pub-capability-and-repo-split.md`): the Pub capability is
/// subordinate to the DART domain — the Dart domain is the unit.
library;

export 'src/dart/dart_command.dart';
export 'src/dart/dart_domain.dart';
export 'src/dart/dart_link_service.dart';
export 'src/dart/pub_links.dart';
export 'src/domain/domain_envelope.dart';
