---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: captured-process-output-escalates-tail-first
  surfaces:
    - "packages/grid_assets/lib/src/code/landing.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: ["revalidate-cfe-diagnostics-lead-before-tail"]
  bead: pow-gy41
  legacy-id: null
---
## Captured process output escalates TAIL-first, advice-stripped, exit-code-led (2026-09-02) — bead `pow-gy41`

**Decision (AI; MECHANISM only).** Every `Escalate` reason in the landing
circuit that embeds CAPTURED PROCESS OUTPUT is assembled the same way:
`'<verb> failed (exit N)<diagnostic-suffix>: <tail>'`, where the tail is
`landReasonTail(planOutputWithoutPubAdvice(output), kRevalidateReasonTailChars)`.
`RevalidateCapability.route` is the first caller;
`packages/grid_assets/lib/src/code/landing.dart`'s private `_truncate`, which
kept the HEAD of the output at a 2000-char cap, is DELETED with its only caller.

**Why the tail, not the head.** `landReasonTail`'s own doc comment already
stated the rule for git/gh output — "the useful line is at the END … taking the
tail keeps the diagnosis, not the noise" — and a Validation Plan's output has
the same shape: `dart pub get`'s advisory block first, the fatal line last. The
live receipt on gate `tranquility-ajfh6r` (node `tg-lohr/land/revalidate`)
carried 2000 characters of `(<version> available)` lines and nothing else, so
the governor had to re-run the plan blind. The rule was already owned; it was
simply not applied to plan output.

**Why strip advice as well as cutting.** A tail alone would spend its budget on
advisory lines when the failure is short. `planOutputWithoutPubAdvice` is a pure,
line-wise filter over two anchored shapes — `<pkg> <ver> (<ver> available)` and
pub's two `outdated` trailers — and is byte-identical on everything else, so it
can never eat a diagnosis. It is public so delivery can reuse it.

**Why the exit code LEADS.** An operator reads the CLASS of failure before the
log; `pathCheckDiagnostic`'s suffix (which only fires on exit 127) keeps its
meaning and sits immediately after the code, before the log.

**Affects:** `packages/grid_assets/lib/src/code/landing.dart`
(`planOutputWithoutPubAdvice`, `kRevalidateReasonTailChars`,
`RevalidateCapability.route`; `_truncate` deleted),
`packages/grid_assets/test/landing_circuit_test.dart`.
