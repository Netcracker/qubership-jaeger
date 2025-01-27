# Readiness probe

* [Readiness Probe](#readiness-probe)
  * [Overview](#overview)
  * [Documents](#documents)
  * [How to start](#how-to-start)
    * [Build](#build)
    * [Smoke tests](#smoke-tests)
    * [How to debug](#how-to-debug)
    * [How to troubleshoot](#how-to-troubleshoot)

## Overview

Readiness probe is used for executing checks and provide custom readiness probe for Jaeger.

## Documents

* [Installation](/docs/public/installation.md)

## How to start

### Build

#### Local build

1. Use WSL or Linux VM
2. Run commands:

    ```bash
    ./build.sh
    ```

### Deploy to k8s

#### Helm

Not applicable because the readiness probe is expected to be deployed along with Jaeger.
For more details, see [Jaeger's Installation Guide: Readiness Probe](/docs/installation.md#readiness-probe).

### Smoke tests

There are no smoke tests.

### How to debug

Readiness probe is a simple application to check if Jaeger is ready. It may be useful to check logs to debug issues.

### How to troubleshoot

Readiness probe issues can be troubleshooted by mostly checking logs from the pods' containers.
