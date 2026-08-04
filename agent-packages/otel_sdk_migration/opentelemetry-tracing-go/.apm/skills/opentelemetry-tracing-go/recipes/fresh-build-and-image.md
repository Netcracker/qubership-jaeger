# Recipe — fresh Go build and container image (Go L5)

When Layer 4 edits exist, run exactly once after L4 and before first runtime deploy.

## Step 0 — Purge stale artifacts

1. clean build outputs (`bin/`, `dist/`, or service-specific output directories);
2. remove stale SUT image tags from active runtime image store;
3. ensure deploy manifest references a session-unique image tag.

## Step 1 — Post-L4 build (once)

Run only after L4 edits. Typical commands from service docs:

- `go test ./...`
- `go build ./...` or module-specific build target.

Pass criteria:

- exit code 0;
- runnable artifact produced from current L4 sources.

## Step 2 — Build image

Build SUT image from post-L4 artifact with session-unique tag.

## Step 3 — Runtime availability

Load/push image into selected runtime environment using documented flow.

## Step 4 — Provenance record

Record in `validationPlan.runtime.buildProvenance`:

- build command;
- image tag;
- whether artifact matches current L4 diff;
- purged stale tags.

Do not start runtime checks until this recipe is completed or blocker is
recorded in `gaps`.
