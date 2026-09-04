---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: app-pr-transport-encodes-utf8-and-escalates-type-first
  surfaces:
    - "packages/github_grid_assets/lib/src/http_transport.dart"
    - "packages/github_grid_assets/lib/src/github_app_client.dart"
    - "packages/github_grid_assets/lib/src/code/github_app_pr_opener.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-b14a
  legacy-id: null
---

# The App transport encodes UTF-8, and its PR opener escalates type-first

## Context and Problem Statement

A delivery failed three times in a minute and the escalation said only that a
request had been echoed. Two defects sat on one path.

`IoGitHubHttpTransport.send` handed a `String` to an `HttpClientRequest` sink;
`dart:io` resolves that sink's encoding to iso-8859-1 whenever `Content-Type`
carries no charset, and `GitHubAppClient.send` sent `application/json` bare, so
latin1 refused the first em dash in the PR body and threw
`ArgumentError.value(<the whole json request>, 'string',
'Contains invalid characters.')`. `ArgumentError.toString` renders that value
through `Error.safeToString`, so the message was ONE multi-kilobyte line ending
in the request's own escaped `\"base\":\"main\"`.

`GitHubAppPrOpener`'s catch-all then interpolated a bare `$error` at the FRONT
of its reason, and `power_station#captured-process-output-escalates-tail-first`
keeps the TAIL — so the operator received the request echo and lost the
exception type entirely. Both attempts were identical and back-to-back because
the cause is deterministic, not transient.

## Decision Outcome

Request-body encoding belongs to the TRANSPORT, and a caught error escalates
type-led with its cause LAST.

`IoGitHubHttpTransport.send` writes `ioRequest.add(utf8.encode(body))`. One sink
covers both callers — the `/pulls` POST and the installation-token exchange,
which also sends `application/json` with no charset — whereas a header-only fix
would depend on every present and future caller remembering the charset.
`GitHubAppClient.send` additionally declares `application/json; charset=utf-8`
for wire correctness, and `token_provider.dart` is left alone because its body
is the ASCII literal `{}`.

`GitHubAppPrOpener`'s catch-all renders
`<generic advice>. Cause (<runtimeType>): <at most 300 characters of $error>`.
The cap is by CHARACTER, never by first line, because `Error.safeToString`
escapes newlines and this error's whole `toString` is a single line. The cause
goes LAST so the tail-first capture keeps it, extending
`power_station#captured-process-output-escalates-tail-first` from captured
process output to a caught exception without amending it. Not throwing is the
only way to honour "never echo the request body": the `toString` that embeds it
belongs to `dart:convert`, which this package cannot edit.

### Consequences

* Good, because a PR body holding any non-Latin-1 character now delivers, and a
  thrown failure names its type in the first words an operator reads.
* Bad, because the 300-character cap still admits a ~243-character prefix of
  whatever value an SDK error embeds; the kilobyte echo is gone, the principle
  of a bounded cause is not absolute.
