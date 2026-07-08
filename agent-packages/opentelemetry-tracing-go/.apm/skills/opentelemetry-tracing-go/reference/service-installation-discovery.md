# Service installation discovery (Go)

Layer 5 runtime validation depends on how the specific Go service is installed
and tested.

## Step 1 — Find install docs

Search:

- `README.md` install/deploy sections;
- `docs/installation/**`;
- `charts/**`, `helm/**`, `values.yaml`;
- `Makefile`, `Taskfile.yml`, `docker-compose*.yml`;
- CI workflows with integration or deploy jobs.

## Step 2 — Derive runtime path

Use service-documented build/deploy flow; do not invent parallel pipelines.
Capture:

- image build command;
- deploy command;
- required dependencies/secrets;
- test command or traffic generation method.

## Step 3 — If unclear, ask user

When install path is not discoverable:

1. ask where service is usually deployed (cluster/local);
2. ask where build credentials are provided;
3. ask whether runtime validation is in scope now.

Keep `runtime.status=manual` until clarified.
