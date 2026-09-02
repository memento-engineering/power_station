---
status: accepted
date: 2026-08-23
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: adr-0005-landing-policy-grade-gated-auto-merge
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "ADR-0005"
---
# ADR-0005 — Landing policy is a per-seat, grade-gated delivery value

**Status:** **Accepted — ratified by Nico, 2026-07-10; reaffirmed 2026-08-21**

## Context

Every GitHub delivery currently opens a pull request and stops. That strands finished work behind a human merge even after the circuit has produced passing code validation and committee grades. Nico directed that good grades should land without a second human ruling.

Delivery is already a composed per-seat `DeliveryMethod`. This decision adds policy values at that seam and does not restore the retired `space up --land` flag.

## Decision

### D1 — Three landing postures are composable values

- `pr-no-merge` opens or reuses a pull request and stops. It remains the default, so existing seat compositions do not change.
- `pr-auto-merge` opens or reuses a pull request, then asks GitHub to enable native auto-merge.
- `direct-merge` opens no pull request and pushes the reviewed branch directly to an unprotected mainline.

The postures are sibling `DeliveryMethod` implementations. Auto-merge delegates only its PR-opening half to `GitHubPrDelivery`; direct merge is independent.

### D2 — Native auto-merge is grade-gated

The default auto-merge policy enables GitHub native auto-merge only when the round's code-validation receipt has rc 0 and no committee grade is below B. B is inclusive: all-B passes and one C refuses. The minimum grade is a value on the composed policy, not a buried constant.

GitHub owns the wait for required checks. The station does not poll or reconcile the green path. The command is queue-compatible and supplies neither a merge strategy nor branch deletion.

### D3 — Refusal degrades loudly

A grade-gate refusal still leaves the pull request open for a human ruling and emits a flare naming the failing receipt. An API refusal to enable auto-merge likewise falls back to `pr-no-merge` and emits a flare naming the reason.

Direct merge first preserves the branch on the remote. If branch protection is present or cannot be ruled out, it emits a refusal flare, returns failure, and performs no base-branch push.

## Ground

This implements Nico's 2026-07-10 directive, reaffirmed 2026-08-21: finished work whose grades justify landing must not wait on a redundant human merge.

`docs/adr/ADR-0004-station-throughput-outranks-staging-ceremony.md` D2 says, “A ready P0 or P1 never waits on a human when the station is halted.” Grade-gated native auto-merge is the delivery mechanism for that throughput rule.

ADR-0004 D3 does not apply: this is a twice-ratified human directive, not an autonomous governor departure. ADR-0004's Consequences require Nico's directives to live in a numbered ADR and never in ADR-0000.

## Consequences

Existing compositions retain `pr-no-merge`. Seats may compose `pr-auto-merge` or `direct-merge` explicitly. CI-failure feedback remains complementary and webhooks remain separate.

The the_grid decision amendment reversing ADR-0006 D3 is owned by follow-up bead `tg-o5z0`, sequenced behind this implementation through link `tranquility-g83gb`; it is not part of this power_station diff.
