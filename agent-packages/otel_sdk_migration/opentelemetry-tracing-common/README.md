# opentelemetry-tracing-common

Shared tracing core for the language-specific tracing skills. It is an internal package: nothing starts a tracing task
here, and it ships no instruction rule, because the language skills pull it in.

Part of the multi-language tracing program — see [`../README.md`](../README.md).

## Pipeline

Layers L2–L5 live here; L1 and runtime execution live in each language package. The full ownership split, the artifact
chain, and the file index are in
[`.apm/skills/opentelemetry-tracing-common/SKILL.md`](.apm/skills/opentelemetry-tracing-common/SKILL.md) — the copy the
agent reads, and the only place they are listed.
