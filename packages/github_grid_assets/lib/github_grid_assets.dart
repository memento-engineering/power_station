/// GitHub App identity and authenticated REST transport for grid extensions.
///
/// This identity-only pack performs no polling, reconciliation, pull-request
/// opening, or bead writes.
library;

export 'src/credentials.dart';
export 'src/github_app_client.dart';
export 'src/http_transport.dart';
export 'src/token_provider.dart';
