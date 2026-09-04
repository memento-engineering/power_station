# The spec record grammar, measured in shadow

GENERATED — `dart run tool/spec_contract_shadow.dart --record` is the only writer, and `test/spec_contract_shadow_test.dart` pins this file to its regeneration. Do not edit by hand.

This runs the record grammar (`parseSpecContract`) over 10 specs that ALREADY SHIPPED through the four spec critics under the PRE-CHANGE contract, and reports what the stronger parser would have said. Nothing here routes: the committee lane set is unchanged, and no critic is removed, skipped or made conditional on this evidence.

## The corpus

| bead | closed | outcome | findings | rules tripped |
| --- | --- | --- | --- | --- |
| `pow-26dd` | 2026-09-03T06:31:44Z | shipped | 31 | acceptanceRecord, decisionRecord, stepField, touchRecord, validationRecord |
| `pow-77g` | 2026-07-12T13:23:49Z | shipped | 38 | acceptanceRecord, decisionRecord, stepCommit, stepField, touchRecord, validationRecord |
| `pow-8qb` | 2026-07-13T05:24:56Z | shipped | 42 | acceptanceRecord, decisionRecord, stepCommit, stepField, touchRecord, validationRecord |
| `pow-d26` | 2026-07-22T03:37:57Z | shipped | 30 | acceptanceRecord, decisionRecord, stepCommit, stepField, touchRecord, validationRecord |
| `pow-emxf` | 2026-09-03T01:58:36Z | shipped | 20 | acceptanceRecord, stepField, validationRecord |
| `pow-gy41` | 2026-09-03T02:25:57Z | shipped | 34 | acceptanceRecord, stepCommit, stepField, touchRecord, validationRecord |
| `pow-kzx` | 2026-07-13T05:29:58Z | shipped | 75 | acceptanceRecord, decisionRecord, stepCommit, stepField, touchRecord, validationRecord |
| `pow-o3ti` | 2026-09-03T13:34:58Z | shipped | 36 | acceptanceRecord, decisionRecord, stepCommit, stepField, touchRecord, validationRecord |
| `pow-vw38` | 2026-09-03T04:37:58Z | shipped | 44 | acceptanceRecord, decisionRecord, stepCommit, stepField, touchRecord, validationRecord |
| `pow-zvaw` | 2026-09-03T13:27:23Z | shipped | 58 | acceptanceRecord, decisionRecord, stepCommit, stepField, touchRecord, validationRecord |

408 findings across 10 shipped specs; 0 parse clean under the new grammar.

## Findings per rule, and the lane that already asks for it

| rule | corpus findings | lane that already asks | clause quoted from that rubric |
| --- | --- | --- | --- |
| `acceptanceRecord` | 99 | — (no lane states it) | — |
| `acceptanceIdDuplicate` | 0 | — (no lane states it) | — |
| `acceptanceIdNotContiguous` | 0 | — (no lane states it) | — |
| `stepTitle` | 0 | — (no lane states it) | — |
| `stepField` | 72 | `plan-completeness` | "the exact test command with expected output" |
| `stepPath` | 0 | `plan-completeness` | "an exact file path from the repo root" |
| `stepCommit` | 33 | `plan-completeness` | "a conventional-commit message" |
| `touchRecord` | 53 | — (no lane states it) | — |
| `decisionRecord` | 50 | `decision-alignment` | "the canonical `<repo>#<slug>` identity" |
| `decisionSectionSilent` | 0 | `decision-alignment` | "never grade the lane clean on a crashed lookup" |
| `validationRecord` | 101 | `acceptance-testability` | "the exact command and its expected result" |
| `validationUnknownCriterion` | 0 | `acceptance-testability` | "item mapped to no criterion" |
| `validationCoverage` | 0 | `acceptance-testability` | "an unmapped criterion caps at C" |

Every quoted clause above is asserted to be a literal substring of the packaged rubric in test, so an overlap claim can never be invented.

## Deterministic false positives, measured

One class is real, and it is reported rather than fixed. The step-opener language is RATIFIED and deliberately unchanged by this work — the new strictness lands on what a step CONTAINS, never on which openers count — and that language matches `<digits>.` or `<digits>)` at the start of ANY line, including an INDENTED prose continuation such as "(line / 107) and before `kSpecReviewCircuit`:". Before the record grammar that only answered a boolean ("does this plan have any ordinal-led step at all"), so an indented prose ordinal cost nothing. The record parser turns every match into a STEP, so such a line becomes a phantom step and then reports the five labeled fields it was never going to carry.

| bead | phantom steps | first phantom opener |
| --- | --- | --- |
| `pow-77g` | 1 | `107) and before `kSpecReviewCircuit`:` |

Every phantom opener above is INDENTED, which is the mechanical signature of a continuation line — a real step opens at column 0. That is the shape a follow-up would narrow on, and narrowing it changes a ratified rule, so it is measured here and left alone.

## The semantic residue — what no record form can decide

| lane | what it uniquely catches | clause quoted from that rubric |
| --- | --- | --- |
| `acceptance-testability` | a mapped command can still be vacuous — the parser sees that a command IS there, never whether it can fail | "a validation item that passes even" |
| `plan-completeness` | a step can carry all five labeled fields and still leave a judgment call to the builder | "A judgment call is any step where the builder must" |
| `decision-alignment` | a citation can RESOLVE and still be applied backwards | "the spec cites a constraint it then applies" |
| `coherence` | a well-formed plan can parallel-build beside a concept the packs already own — no record form can see a duplicate abstraction | "A coherent spec extends what is there" |

## What this corpus does and does NOT establish

Every entry PREDATES the grammar. Its architect was never told the record forms, so each finding above measures MIGRATION COST — the distance between what the old brief asked for and what the new one does — and not critic redundancy. A high count on a rule says the old brief was silent about it, not that a lane was failing to catch it. Some counts are contract FRICTION rather than sloppiness — a gate-only final step writing `Commit: none` is a deliberate, readable choice the new grammar refuses — and those are exactly the calls a follow-up should revisit with the numbers above in hand.

The overlap column is therefore the weaker claim it looks like: it says a lane ASKS for the same property in prose, not that the lane RELIABLY caught it — these specs passed those lanes carrying the deviations counted above. Establishing redundancy needs a corpus written UNDER the new brief, where a deterministic finding and a lane verdict are answering the same question about the same document.

So: no critic may be removed, skipped or made conditional on this evidence. Structure and referential integrity move to code; whether a test PROVES behaviour, whether a plan is COHERENT, and whether a decision is INTERPRETED correctly stay inference, and the residue table above is quoted from the lanes that own them.
