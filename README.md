# qubership-jaeger

[Jaeger](https://github.com/jaegertracing/jaeger) helm charts for Qubership.

## Development
Before push your commits and create PR run linters and test.
* SuperLinter
```shell
docker run \
  -e RUN_LOCAL=true \
  -e VALIDATE_JSCPD=false \
  -e DEFAULT_BRANCH=$(git rev-parse --abbrev-ref HEAD) \
  --env-file .github/super-linter.env \
  -v ${PWD}:/tmp/lint \
  --rm \
  ghcr.io/super-linter/super-linter:$(sed -nE 's#.*uses:\s+super-linter/super-linter@([^\s]+).*#\1#p' .github/workflows/super-linter.yaml)
```

## Documents

* [docs](docs)

## Application and components

Jaeger application:

* [https://github.com/jaegertracing/jaeger](https://github.com/jaegertracing/jaeger)

Included components:

* [jaeger](https://github.com/jaegertracing/jaeger)
* [readiness-probe](readiness-probe)
* [deployment-status-provisioner](https://github.com/Netcracker/qubership-deployment-status-provisioner)
