# Codemod automation in the tracing skills — status and why it is on hold

Only this document is committed. The automation itself is not, because it does not hold up on real
repositories yet.

## The idea

The tracing skills run a five-layer pipeline: discover what exists, judge what works, score maturity,
transform, validate. Layer 4 (transformation) splits cleanly in two:

- **decision-bearing work** — propagation format, service naming, sampling intent, log correlation,
  endpoint filtering, async context. Every one of these depends on the fleet, the peers, or the
  operator. An agent has to reason about them.
- **mechanical work** — swap the retired tracing libraries for the OpenTelemetry ones, write the same
  handful of canonical export keys. A pure function of the repository.

The mechanical half looked like a job for a codemod engine: a declarative recipe, versioned with the
skill, producing a reviewable diff instead of a claim that the edits were made. Java was the trial
language (OpenRewrite); the same shape was intended per language.

## Why it does not work

Five failure modes, in descending order of how much damage they do. None is specific to one language
or one engine — they follow from what a static recipe can and cannot know.

**1. A missed assumption is silent.** A recipe encodes where things live: which file holds the
configuration, how the modules are laid out, what the manifest looks like. Real projects deviate
constantly and legitimately. When a rule's path or pattern does not match, nothing happens and the run
reports success. Silence is indistinguishable from "nothing needed here". This is the whole problem in
one sentence: the tool fails into a state that reads as done.

**2. The pipeline already knows better, and cannot say so.** Layer 1 resolves the real layout — the
actual config path, the actual module graph — and the skill explicitly warns that writing to the
conventional location produces a green diff and an unchanged deployment. A recipe file is a static
artifact with no parameters, so that finding never reaches the run. The two halves of the same skill
disagree, and the dumber one wins.

**3. Removal rules see declarations, not the resolved graph.** A retired library pulled in by a
platform dependency survives a run that reports it removed. The manifest reads clean while the class is
still on the classpath at startup. Correct behaviour for the rule, wrong conclusion for the reader.

**4. Scope control is weak in multi-module repositories.** Rules either under-apply (touch one module
when the change belongs everywhere) or over-apply (write into every module including ones with no
relation to tracing). Both need manual cleanup, and the cleanup is larger than the edit.

**5. Option semantics vary between rules that look alike.** Two rules a few lines apart in the same
file can take an identically named option with different meaning — one wants a symbol pattern, the
other a coordinate glob. The mistake is invisible on reading and only surfaces when the run aborts.

## The payoff is thinner than it looks

Even working perfectly, the codemod covers the mechanical half only — and on the trial repository that
half was a minority of the change set. Exclusions for transitively-pulled legacy, the propagation
extension, endpoint filtering, log correlation, async context, deployment values, and documentation
were all decision-bearing or layout-dependent, and all landed by hand anyway.

So the honest trade is: a thin slice of automation in exchange for a new failure surface that fails
quietly. That is a bad trade until failure mode 1 is closed.

## What was tried

Mitigations already in the package, and what each actually bought:

| Mitigation | Result |
| --- | --- |
| Pin engine and rule-library versions; forbid floating versions | Works. Removes upstream non-determinism from the diff |
| Fail hard on an invalid or mistyped recipe name | Works. Turned one silent no-op into a loud abort |
| Mandatory chat brief after every run, naming which kind of empty diff it is | Partly works. Surfaced the biggest defect — but relies on the agent counting outcomes, not on the tool reporting them |
| A read-only scan recipe feeding Layer 1, re-run after migration | Works, and is the most valuable piece. Catches "removed but still resolved" |
| "Repeat until zero hits" instruction for the resolved graph | Works. Each exclusion uncovers the next parent; one pass is never enough |
| Guardrail: never exclude a library before confirming it does not need the retired tracer | Works. Prevented a change that would have broken startup |
| Run against the whole repository, then clean up the spread by hand | Survivable, not good. The cleanup outweighed the edit |

What was **not** tried, and is the obvious next step: passing the Layer 1 findings into the run as
parameters, and treating "no rule matched" as a hard failure rather than an outcome.

## Evidence

One full end-to-end trial on a real service — nine modules, a retired tracing stack, migration
validated in a live cluster against a real trace backend. The migration itself passed. The codemod's
own contribution was about half of the dependency work and **none** of the configuration work, while
reporting success on both.

That single run also produced eleven concrete defects across the recipe and its surrounding
instructions. They are worth re-deriving from a fresh trial rather than trusting a list written against
one repository.

## Where this leaves the idea

Three options, in the order they should be considered:

1. **Make the recipe a function of discovery.** Parameterize paths and scope from Layer 1, and fail the
   run when an expected edit finds no target. This is the only version of the idea worth shipping.
2. **Keep the read-only scan, drop the rewriting.** The scan recipe pays for itself: it resolves the
   dependency graph properly and is the check that catches an incomplete migration. The rewriting is
   what carries the risk.
3. **Drop the codemod path entirely** and keep the analysis plus hand-applied recipes. This is what the
   trial effectively did, and it is what produced a correct result.
