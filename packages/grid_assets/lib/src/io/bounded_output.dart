/// The ONE output bound every vended verb in this pack renders through.
///
/// `power_station#a-mechanical-lookup-is-a-vended-command-with-a-bounded-output`
/// names three properties a vended command owes its reader — a hard cap, an
/// explicit truncation marker, and a structured result — and is explicit about
/// WHERE they live: they are "implemented once in the CLI SDK", because "a
/// per-command implementation is the same failure this entry exists to stop,
/// one layer down". This library is that one implementation, and the verbs that
/// bound their output consume it rather than re-deriving it.
///
/// It owns exactly the GENERIC half: the cap, the predicate BOTH renderings of
/// a result must satisfy, the search for the largest candidate that fits, and
/// the marker contract a trim policy must honour. It owns none of the
/// type-specific half — WHICH material a verb gives up first, in what units it
/// counts what it withheld, and where it tells the reader to ask for the rest,
/// stays with the verb, because that is the only place that knows.
///
/// Not to be confused with `BoundedTextBudget` of `code/describe_manifest.dart`:
/// that clamps ONE plain model-input stream at a line boundary and leaves the
/// omission prose to its caller. This selects between whole rendered candidates
/// against BOTH of a command's renderings.
library;

import 'dart:convert';

/// The HARD ceiling on one rendered result, in UTF-8 bytes, counting the
/// trailing newline the command writes.
///
/// ONE value for the whole pack. It binds BOTH of a command's renderings — the
/// plain text and the single-line JSON object — because a verb that caps only
/// the rendering its own suite happens to exercise leaves the other unbounded,
/// and the unbounded one is the one a skill parses.
const int kBoundedOutputCapBytes = 8000;

/// [complete] when both of its renderings already fit
/// [kBoundedOutputCapBytes], and otherwise the largest [trim] candidate that
/// does.
///
/// [renderPlain] and [renderJson] return their text WITHOUT the command's final
/// newline; this measures each one WITH it, because that newline is a byte the
/// reader pays. A result is admitted only when BOTH fit.
///
/// [trim] is the caller's POLICY, evaluated over a budget in
/// `0..maximumTrimBudget`. Two obligations come with it:
///
/// * It is MONOTONE — a larger budget never yields a smaller rendering — which
///   is what makes the search below a binary one rather than a scan.
/// * Every candidate that omits material NAMES it: what was withheld, how much
///   (UTF-8 bytes, or whole records where the policy drops records), and the
///   command or path that retrieves it. Silent truncation is the failure the
///   ratified entry above singles out as worse than no cap at all.
///
/// Nothing here slices the caller's text. The only strings it reads are the
/// finished renderings, and the only thing it decides is which candidate to
/// return; a rune, a line record and a JSON envelope are the policy's to keep
/// whole.
///
/// `trim(0)` is the policy's whole-record fallback and the floor of the search.
/// It MUST fit: a policy whose smallest candidate is over the cap has no
/// bounded answer at all, so this throws a [StateError] naming the cap rather
/// than emit an unbounded one.
T boundedOutput<T>({
  required T complete,
  required int maximumTrimBudget,
  required String Function(T value) renderPlain,
  required String Function(T value) renderJson,
  required T Function(int budget) trim,
}) {
  if (maximumTrimBudget < 0) {
    throw ArgumentError.value(
      maximumTrimBudget,
      'maximumTrimBudget',
      'a trim budget counts bytes, so it is never negative',
    );
  }
  bool fits(T value) =>
      renderedBytes(renderPlain(value)) <= kBoundedOutputCapBytes &&
      renderedBytes(renderJson(value)) <= kBoundedOutputCapBytes;

  if (fits(complete)) return complete;

  var best = trim(0);
  if (!fits(best)) {
    throw StateError(
      'no bounded rendering: the zero-budget fallback is '
      '${renderedBytes(renderPlain(best))} plain and '
      '${renderedBytes(renderJson(best))} JSON UTF-8 bytes, over the '
      '$kBoundedOutputCapBytes-byte cap',
    );
  }
  var low = 1;
  var high = maximumTrimBudget;
  while (low <= high) {
    final mid = low + (high - low) ~/ 2;
    final candidate = trim(mid);
    if (fits(candidate)) {
      best = candidate;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return best;
}

/// What [rendering] costs the cap: its UTF-8 length plus the one newline the
/// command writes after it.
///
/// The single measurement both this library and a verb's own suite use, so what
/// the bound is computed against is exactly what is printed.
int renderedBytes(String rendering) => utf8.encode(rendering).length + 1;
