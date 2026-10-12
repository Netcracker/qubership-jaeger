# Service installation discovery — Python delta

Shared steps 1–4, evidence rules, and the out-of-scope list:
[`opentelemetry-tracing-common/reference/service-installation-discovery.md`](../../opentelemetry-tracing-common/reference/service-installation-discovery.md).

Python adds the signals below.

## Step 1 — extra search locations

- `pyproject.toml` `[project.scripts]`, `setup.py` / `setup.cfg` entry points;
- `manage.py`, `gunicorn.conf.py`, `uvicorn` / `gunicorn` entrypoints, `Procfile`;
- `requirements*.txt` and lockfiles (`poetry.lock`, `uv.lock`, `Pipfile.lock`).

## Step 2 — extra capture

- dependency install command — `pip install -r ...`, `poetry install`, or `uv sync`;
- app-server entrypoint: uvicorn / gunicorn / uwsgi / `manage.py`, **worker count**, and whether `--preload` is set.

The app-server entrypoint decides tracing correctness, not just startup. The worker model and `--preload` decide where
the SDK must be initialized: a provider created before the fork is inherited broken by every worker. See
[`../recipes/config-migration.md`](../recipes/config-migration.md) §Short-lived processes and the fork-server note.
