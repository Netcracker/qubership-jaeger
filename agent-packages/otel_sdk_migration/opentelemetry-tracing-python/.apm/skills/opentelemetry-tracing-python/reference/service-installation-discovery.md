# Service installation discovery (Python)

Layer 5 runtime validation depends on how the specific Python service is installed
and run.

## Step 1 — Find install docs

Search:

- `README.md` install/deploy sections;
- `docs/installation/**`;
- `charts/**`, `helm/**`, `values.yaml`;
- `Dockerfile`, `docker-compose*.yml`, `Makefile`, `Taskfile.yml`;
- `pyproject.toml` scripts / `[project.scripts]`, `manage.py`, `gunicorn.conf.py`,
  `uvicorn`/`gunicorn` entrypoints, `Procfile`;
- CI workflows with integration or deploy jobs.

## Step 2 — Derive runtime path

Use the service-documented build/run flow; do not invent a parallel pipeline.
Capture:

- dependency install command (`pip install -r ...` / `poetry install` / `uv sync`);
- image build command;
- deploy command;
- app server entrypoint (uvicorn/gunicorn/uwsgi/manage.py, worker count, `--preload`);
- required dependencies/secrets;
- test command or traffic generation method.

The app-server entrypoint matters for tracing: worker model and `--preload`
decide where the SDK must be initialized (see
[`../recipes/config-migration.md`](../recipes/config-migration.md) fork-server note).

## Step 3 — If unclear, ask user

When the install path is not discoverable:

1. ask where the service is usually deployed (cluster/local);
2. ask where build credentials / private index access are provided;
3. ask whether runtime validation is in scope now.

Keep `runtime.status=manual` until clarified.
