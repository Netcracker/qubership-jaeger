# Recipe — fresh Maven build and container image (Java L5)

**When:** exactly **once per session**, **after all Layer 4 edits**, **before**
the first runtime deploy of the SUT. Not during L1–L3 analysis. Not again for
runtime e2e if the post-L4 build already succeeded and L4 files are unchanged.

Every runtime e2e must use the **post-L4** runnable artifact and container
image — never a pre-L4 build, cached `target/` output from before
transformation, or a pre-existing local tag.

Planning-only passes (no L4 edits, audit-only) **skip this recipe** entirely
and set `validationPlan.runtime.status` to `manual`.

## Why

Quarkus/Spring bake instrumentation at build time. A stale image proves tracing
works on **some** build, not on the current diff.

## Step 0 — Purge stale artifacts (mandatory)

Run this **before** Maven package and before image build:

1. Clean the service module outputs (or run a clean build target).
2. Remove cached **SUT-only** image tags from the active runtime image store.
3. Ensure the upcoming deploy manifest references a new session-unique tag.

Record purged tags under `validationPlan.runtime.buildProvenance.purgedImages`.

## Step 1 — Maven package (mandatory, once after L4)

Run **only after** L4 file edits are complete. Do **not** run Maven during
L1–L3 or as a "trial" before transformation.

Derive the exact command from install docs / CI / project build scripts.
Typical pattern: `mvn --batch-mode clean package -pl <module-path> -am -DskipTests`.

**Pass criteria:**

- exit code is 0;
- fresh runnable artifact exists (for Quarkus usually `*-runner.jar`);
- runtime startup metadata includes the intended instrumentation mechanism.

## Step 1b — Reuse check (before runtime, no second build)

When runtime e2e starts after Step 1 already succeeded in this session:

1. Confirm no L4 file changed since Step 1 completed.
2. Confirm runnable artifact mtime is **after** the last L4 edit.
3. Confirm the deploy manifest image tag matches Step 2 output.

If all hold, **skip** another full rebuild.  
If L4 changed after Step 1, rerun Steps 0–3 once and replace provenance.

On HTTP 401, record `runtime.buildBlocked: private-maven-registry` in `gaps`;
do **not** fall back to cached images. See
[`../reference/build-preconditions.md`](../reference/build-preconditions.md).

## Step 2 — Container image (mandatory, same session as Step 1)

Build from the service Docker context using fresh post-L4 artifacts.
Use a **session-unique tag** (git short SHA, timestamp, or equivalent).

## Step 3 — Runtime image availability (mandatory)

Make the new image available to the selected runtime environment using the
environment's documented import/push flow. Do not assume a specific runtime.

## Step 4 — Record provenance (mandatory)

Set `validationPlan.runtime.buildProvenance`:

```json
{
  "source": "fresh-build",
  "matchesL4": true,
  "mavenCommand": "mvn --batch-mode clean package -pl ... -am -DskipTests",
  "imageTag": "<service-image>:<session-tag>",
  "runnerJar": "<module>/target/*-runner.jar",
  "purgedImages": ["<old-tag-1>"],
  "detail": "Built in this session after L4; stale artifacts removed before build"
}
```

Post a one-line chat confirmation:

> Fresh build: `<runner-jar>` -> image `<tag>` produced after L4 at `<timestamp>`.

## Forbidden shortcuts

| Shortcut | Verdict |
|----------|---------|
| `mvn clean package` during L1–L3 analysis | **forbidden** |
| Second full rebuild when post-L4 build is still valid | **forbidden** |
| Deploy pre-existing local tags without post-L4 build | `runtime.status` max **`fail`** |
| Skip clean step and reuse stale build outputs | **invalid** |
| Claim runtime `pass` when no post-L4 Maven build ran | **invalid** |
| Attach OTel javaagent to Quarkus instead of extension path | **forbidden** (see L4 gate) |

## User-facing brief (mandatory before runtime deploy)

```markdown
### L5 Fresh build — <service-name>
- **Purged:** build outputs + stale image tags
- **Maven:** command -> exit 0, runnable artifact path
- **Image:** <name>:<session-tag> available in target runtime
- **Matches L4:** yes / no (feature evidence)
```

Do not start runtime validation until this brief is posted (or `gaps` records a
build blocker).
