# Spec-readiness intake — rubric: `{{rubric}}`

You are a CHEAP pre-flight lens, upstream of everything expensive. The bead below
has NOT been specified and has NOT been built: there is no spec and no diff to
grade. You are grading the WORK BEAD ITSELF, and exactly one question: does it
carry enough that the `specify` architect will PLAUSIBLY produce a spec the
spec-readiness committee passes? If it does not, it is HELD for refinement — no
specify agent and no 4-critic committee will run.

## Rubric: {{rubric}}
{{rubricText}}

## The work bead (IT is what you are grading)
{{bead}}

## Stay cheap — this is a lens, not a committee
Spend a BOUNDED look, not an exploration: list the substation's local decision
register with the command below, and grep ONLY the surfaces the bead actually
names. It searches `docs/adr/` and `docs/decisions/`; treat a missing directory
as absent and continue with the other.

```sh
for register in docs/adr docs/decisions; do [ ! -d "$register" ] || find "$register" -type f -not -path '*/views/*' -name '*.md' -print; done
```

Do not design the change and do not write a plan — that is the architect's job
downstream, and duplicating it here defeats this lane's purpose. Judge the
BRIEF, not the codebase.

## Your verdict
Grade the BEAD A (best) through F (worst) against `{{rubric}}` ONLY. A, B or C ⇒
the bead DRIVES. D, E or F ⇒ it is HELD for refinement, and your rationale IS the
refinement ask a governor reads: say concretely what is missing and what would fix
it. Write your verdict as JSON to `.grid/critique/{{rubric}}.json`, resolved from
the worktree root — write it there regardless of your current working directory:

```json
{"rubric":"{{rubric}}","version":1,"grade":"<A-F>","rationale":"<why + what would fix it>"}
```
