# Recipe — fresh Python build and container image (Python L5)

When Layer 4 edits exist, run exactly once after L4 and before first runtime deploy.

Python is interpreted — there is no compiler to catch a broken migration. The
"fresh build" therefore means a **clean dependency install** (so the new OTel
packages are actually in the image) plus a smoke import and test run, not a
compile step.

## Step 0 — Purge stale artifacts

1. clean build outputs (`build/`, `dist/`, `*.egg-info/`, stray `__pycache__/`);
2. remove stale SUT image tags from the active runtime image store;
3. ensure the deploy manifest references a session-unique image tag.

## Step 1 — Post-L4 clean install + smoke (once)

Run only after L4 edits. Typical commands from service docs:

- `pip install -r requirements.txt` (clean venv) / `poetry install` / `uv sync`;
- smoke-import the **OTLP exporter**, not just the SDK, plus the service entry
  module:

  ```shell
  python -c "from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter; print('otlp ok')"
  ```

  A successful install does **not** prove the exporter imports. `import
  opentelemetry.sdk.trace` alone passes even when export is broken, because the
  SDK does not pull `opentelemetry-proto` / `protobuf`; the exporter does.
- `pytest` (or the documented test command) when a suite exists.

Pass criteria:

- clean install exits 0 with the L4 dependency set resolved;
- the OTLP exporter **and** the service module import without error;
- documented tests pass (or are recorded as absent in `gaps`).

> **Common failure — protobuf/proto mismatch.** If the exporter import raises
> `TypeError: Descriptors cannot be created directly` (or "generated code is out
> of date … regenerate with protoc >= 3.19"), the resolver installed an
> `opentelemetry-proto` whose generated code is incompatible with the installed
> `protobuf` runtime — typically an ancient `opentelemetry-exporter-otlp-proto-*`
> pulled in against a newer `protobuf`, i.e. the split version set
> [`dependency-migration.md`](dependency-migration.md) warns about. Fix by
> aligning the whole OTel set to one release train (§Manifest guardrails there),
> not by pinning `protobuf` down. This is resolver-agnostic — pip, poetry, conda,
> and OS packages can all produce it.

## Step 2 — Build image

Build the SUT image from the post-L4 tree with a session-unique tag. Confirm the
image's installed packages include the L4 additions
(`pip show opentelemetry-sdk` inside the image, or inspect the lock file baked in).

## Step 3 — Runtime availability

Load/push image into the selected runtime environment using the documented flow.

## Step 4 — Provenance record

Record in `validationPlan.runtime.buildProvenance`:

- install/build command;
- image tag;
- whether the image's dependency set matches the current L4 diff;
- purged stale tags.

Do not start runtime checks until this recipe is completed or a blocker is
recorded in `gaps`.
