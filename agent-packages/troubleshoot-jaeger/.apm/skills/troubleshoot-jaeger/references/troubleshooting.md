# Qubership Jaeger — troubleshooting

> Cases marked with an external source are compiled from vendor documentation and public issue reports. They are
> pending verification by a maintainer against a real installation.

This reference covers the Jaeger stack deployed by the `qubership-jaeger` Helm chart: Jaeger v2 collector and query,
the external trace store (Cassandra, OpenSearch/Elasticsearch, or remote gRPC), the readiness-probe sidecar, the Envoy
auth proxy, and the Helm install path itself. The store is never deployed by this chart — it must already exist.

## Helm install and upgrade

### Helm upgrade fails with `no matches for kind "Ingress" in version "networking.k8s.io/v1beta1"`

**Symptoms:**

* `helm upgrade` fails and reports `no matches for kind "Ingress" in version "networking.k8s.io/v1beta1"`.
* The failure started after the Kubernetes cluster was upgraded to 1.22 or later.
* A previously working Jaeger release will no longer upgrade.

**Root cause:**

Helm records every object it created in a release secret named `sh.helm.release.<version>.<name>.<version>`. Before
upgrading, Helm reads the objects listed there from Kubernetes. A release created on an older cluster lists the Ingress
under `networking.k8s.io/v1beta1`, an API that Kubernetes removed in 1.22. Helm asks the cluster for an object whose
API no longer exists and the upgrade fails.

This happens when Kubernetes is upgraded to 1.22 or later *before* the Jaeger deployment is upgraded.

**How to check:**

1. Confirm the cluster version is 1.22 or later — the removal only affects these versions.

   ```bash
   kubectl version --short
   ```

2. List the Helm release secrets for the namespace. The stored manifest of the newest revision is the one Helm reads.

   ```bash
   kubectl get secrets -n <namespace> --field-selector type=helm.sh/release.v1
   ```

**How to fix:**

Both options below discard the release history that pins the removed API. Pick the first one that fits.

1. **DANGEROUS — deletes the Helm release history for this release; Helm loses track of the objects it created and a
   later `helm uninstall` will not clean them up.** Remove the release secrets that record the old API version. Back
   them up first so the history can be restored.

   ```bash
   kubectl get secrets -n <namespace> --field-selector type=helm.sh/release.v1 -o yaml > release-secrets-backup.yaml
   kubectl delete secret sh.helm.release.<version>.<name>.<version> -n <namespace>
   ```

2. **DANGEROUS — a clean install removes the running Jaeger deployment; trace ingestion stops until the new release is
   ready. Traces already written to the external store are kept, because the store is not part of the release.** Make a
   clean install of Jaeger.

**How to avoid this issue:**

Upgrade in this order when a service supports migration to the new Kubernetes APIs:

1. Upgrade the service to a version that works on the new Kubernetes.
2. Only then upgrade Kubernetes.

**Sources:**

* [Deprecated API migration guide — Kubernetes](https://kubernetes.io/docs/reference/using-api/deprecation-guide/#v1-22)
* [Ingress v1.22 — Kubernetes](https://kubernetes.io/docs/reference/using-api/deprecation-guide/#ingress-v122)

### Helm upgrade fails with a labels and annotations validation error

**Symptoms:**

* `helm upgrade` fails with an error about label or annotation validation.
* The resource named in the error already exists in the namespace and was created outside Helm.

**Root cause:**

Helm does not allow a resource to be owned by more than one release. During a Jaeger upgrade the chart may create a
resource that already exists and was created outside Helm. Helm refuses to adopt it unless the resource carries the
labels and annotations that mark it as belonging to this release.

**How to check:**

1. Read the labels and annotations on the resource named in the error, and check whether
   `app.kubernetes.io/managed-by`, `meta.helm.sh/release-name`, and `meta.helm.sh/release-namespace` are present and
   match this release.

   ```bash
   kubectl get <kind> <name> -n <namespace> -o jsonpath='{.metadata.labels}{"\n"}{.metadata.annotations}{"\n"}'
   ```

**How to fix:**

1. Set the following label and annotations on the existing resource so Helm adopts it into this release.

   ```yaml
   labels:
     app.kubernetes.io/managed-by: Helm
   annotations:
     meta.helm.sh/release-name: <RELEASE_NAME>
     meta.helm.sh/release-namespace: <RELEASE_NAMESPACE>
   ```

**Sources:**

* [Helm not creating the resources — Stack Overflow](https://stackoverflow.com/questions/62964532)
* [Adopt resources into a release — helm/helm#7649](https://github.com/helm/helm/pull/7649)

### Helm install fails with `Invalid duration format`

**Symptoms:**

* `helm install` or `helm upgrade` fails at render time, before anything is created in the cluster.
* The error reads `Invalid duration format: <value>. Must be a sequence of digits + units (h,m,s).`

**Root cause:**

Since Jaeger 2.x, `cassandraSchemaJob.ttl.trace` and `cassandraSchemaJob.ttl.dependencies` must carry a unit — `s`,
`m`, or `h`. The chart validates both values while rendering and calls `fail` on anything that is neither `0`, nor a
bare integer, nor a digits-plus-units string. A value such as `2d` or `172800ms` aborts the release.

A bare integer is accepted and silently read as seconds: `172800` becomes `172800s`.

**How to check:**

1. Read the TTL values you are passing and confirm each is `0`, a bare integer, or digits followed by `h`, `m`, or `s`.

   ```bash
   helm get values <release> -n <namespace> | grep -A3 ttl
   ```

**How to fix:**

1. Set both TTL values with a supported unit, then re-run the install.

   ```yaml
   cassandraSchemaJob:
     ttl:
       trace: 172800s
       dependencies: 0
   ```

**How to avoid this issue:**

Set the correct TTL on the first install. Cassandra TTL is applied when the keyspace is created and **cannot be
changed** by a Jaeger upgrade — see the case "Cassandra TTL cannot be changed by an upgrade".

**Sources:**

* `charts/qubership-jaeger/templates/_helpers.tpl` — `cassandraSchemaJob.validateTTLDuration`
* `docs/installation.md` — "Since Jaeger release `2.x`, `cassandraSchemaJob.ttl` parameters (`trace` and
  `dependencies`) must be set with a suitable unit"

### Collector crashes at startup after setting `jaeger.storage.type: opensearch`

**Symptoms:**

* `helm install` succeeds with no error, but the collector pod never becomes ready.
* The collector container exits at startup or restarts repeatedly.
* The rendered collector config has an empty `backends:` map and an empty `trace_storage:` value.
* The value `opensearch` was used for `jaeger.storage.type`, often copied from the quickstart example in `README.md`.

**Root cause:**

The chart accepts exactly three storage types: `cassandra`, `elasticsearch`, and `remotegRPC`. OpenSearch is selected
with `elasticsearch`, not `opensearch`. The templates branch on the exact string, and `values.schema.json` defines no
enum for this field, so an unrecognized value passes schema validation, matches no branch, and renders a config with no
storage backend. Helm reports success because the failure only surfaces when the collector parses its config.

The quickstart example in the repository's own `README.md` uses `type: opensearch`, which reproduces this.

**How to check:**

1. Read the storage type currently set for the release.

   ```bash
   helm get values <release> -n <namespace> | grep -A2 storage
   ```

2. Read the rendered collector config and check whether `backends:` and `trace_storage:` have values.

   ```bash
   kubectl get configmap <release>-collector -n <namespace> -o yaml
   ```

**How to fix:**

1. Set the storage type to `elasticsearch`, which is the correct value for both Elasticsearch and OpenSearch, then
   upgrade the release.

   ```yaml
   jaeger:
     storage:
       type: elasticsearch
   ```

**How to avoid this issue:**

Use only `cassandra`, `elasticsearch`, or `remotegRPC`. Treat `elasticsearch` as the OpenSearch setting too — the
chart, the `values.yaml` comment, and the templates all use that one name for both stores.

**Data to collect:**

* The output of `helm get values <release> -n <namespace>`.
* The collector ConfigMap.
* The collector container logs from the first restart.

**Sources:**

* `charts/qubership-jaeger/values.yaml` — "Specify type of storage for jaeger. E.g. `elasticsearch`, `cassandra` or
  `remotegRPC`."
* `charts/qubership-jaeger/templates/collector/configmap-config.yaml` — the storage branches

## Cassandra storage

### Cassandra schema job, collector, or query fails to start

**Symptoms:**

* The Cassandra schema job does not complete, failing with errors related to the Cassandra connection.
* The collector and query pods do not start.
* Errors appear in the Cassandra logs.

**Root cause:**

The schema job cannot reach Cassandra, or cannot authenticate to it, or is not permitted to create the keyspace. Any of
these leaves the schema absent, and the collector and query pods that depend on it cannot start.

**How to check:**

Check the following:

1. The Cassandra connection string is valid, and Cassandra is running and operable.
2. Cassandra's `user` and `password` are valid.
3. The Cassandra `datacenter` is valid for your Cassandra cluster.
4. The keyspace can be created in Cassandra.
5. TLS parameters are configured if TLS is enabled and required for Cassandra.
6. Cassandra has at least 2 nodes — 3 or more is better — if Jaeger is installed in the `prod` mode. See the case
   "Jaeger does not work when `mode: prod` is used with one Cassandra node".
7. View the errors from the Cassandra logs if they exist.

   ```bash
   kubectl logs job/<release>-cassandra-schema -n <namespace>
   ```

**How to fix:**

1. Correct whichever connection, credential, datacenter, or TLS setting the checks above identified, then re-run the
   install or upgrade so the schema job runs again with the corrected values.

**Data to collect:**

* The logs of the Cassandra schema job pod.
* The logs of the collector and query pods.
* The Cassandra server logs covering the time of the failure.

**Sources:**

* `docs/troubleshooting.superseded.md` — "Jaeger `collector`, `query`, `cassandra schema job` can't start/failed"

### Jaeger does not work when `mode: prod` is used with one Cassandra node

**Symptoms:**

* The Cassandra schema is not created and the schema job fails.
* Jaeger pods do not start.
* The Cassandra cluster has only one node and `cassandraSchemaJob.mode` is set to `prod`.
* Reads or writes fail with a consistency error such as `Cannot achieve consistency level QUORUM`.

**Root cause:**

`mode: prod` creates the keyspace with `NetworkTopologyStrategy` and a replication factor of 2, which asks Cassandra to
keep two replicas of every row. A single-node cluster can only ever hold one.

This repository states the outcome plainly: the `mode: prod` **can't be used** if you have **only 1** Cassandra node —
Jaeger won't allow to create of a schema and other Jaeger pods won't start with this configuration.

Note on the mechanism, for reading the logs: Cassandra itself accepts a `CREATE KEYSPACE` whose replication factor
exceeds the node count — it does not reject it at creation time. The shortfall surfaces when a query needs more
replicas than exist, as an unavailability or consistency error. So the visible failure may be a failed schema job, or
it may be pods that start and then fail every read and write.

**How to check:**

1. Count the nodes in the Cassandra cluster.

   ```bash
   kubectl get pods -n <cassandra-namespace> -l <cassandra-selector>
   ```

2. Read the mode currently configured for the release.

   ```bash
   helm get values <release> -n <namespace> | grep -A2 cassandraSchemaJob
   ```

3. If the keyspace already exists, read the replication factor it was created with and compare it against the node
   count from step 1.

   ```bash
   cqlsh <cassandra-host> -u <username> -p <password> -e "DESCRIBE KEYSPACE <keyspace>;"
   ```

**How to fix:**

1. With only one Cassandra node, use `test`, which selects a SimpleStrategy without data replication, then re-run the
   install.

   ```yaml
   cassandraSchemaJob:
     mode: test
   ```

2. If the deployment must run in `prod` mode, add nodes to the Cassandra cluster first — 2 or more, 3 or more
   recommended — and then install with `mode: prod`.

**How to avoid this issue:**

Choose the mode from the real node count before the first install: `prod` for 2 or more nodes, `test` for one. With 2
or more nodes you may still use a SimpleStrategy without data replication if you want.

**Sources:**

* `docs/installation.md` — "**Warning!** The `mode: prod` **can't be used** if you have **only 1** Cassandra node."

### `gocql: no hosts available in the pool`

**Symptoms:**

* In collector and query logs, or even in the Query UI, you can find the following log:

  ```text
  error reading service_names from storage: gocql: no hosts available in the pool
  ```

* Jaeger stops reading from or writing to Cassandra after Cassandra was restarted.

**Root cause:**

Jaeger, using Cassandra as storage, by default uses a `SimpleRetryPolicy` from the Gocql module. When Jaeger can't
execute a query it retries the query, waiting the specified time between a specified number of retries. By default
Jaeger does `3` retries and waits `1m` between them, so it retries for `3 minutes` in total. If Jaeger can't
successfully retry the query for `3 minutes` it marks the Cassandra host as not available and won't use it next.

**How to check:**

1. Verify that Cassandra is available and operable now.

   ```bash
   kubectl get pods -n <cassandra-namespace>
   ```

2. Read the collector and query logs to confirm the pool error is still being produced.

   ```bash
   kubectl logs deployment/<release>-collector -n <namespace>
   ```

**How to fix:**

1. Verify that Cassandra is available and operable now. Do not restart Jaeger until it is — the restart will not help
   while Cassandra is still down.
2. **DANGEROUS — restarting interrupts trace ingestion and in-flight spans are lost until the new pods are ready.**
   Restart the collector and query pods.

   ```bash
   kubectl rollout restart deployment/<release>-collector deployment/<release>-query -n <namespace>
   ```

**How to avoid this issue:**

**Warning!** Before you apply the steps below, read the related problem
the case "`connection: no route to host`" and apply the solution described there. When using a
Cassandra cluster with one node, its **IP always will be changed** after Cassandra's restart. Even with 3 or more nodes
a situation might occur when all nodes restart and change their IPs.

The retry count and wait interval can be specified using CLI arguments or environment variables:

* CLI arguments
  * `--cassandra.reconnect-interval` (default `1m`) — reconnect interval to retry connecting to downed hosts
  * `--cassandra.max-retry-attempts` (default `3`) — the number of attempts when reading from Cassandra
* ENV variables
  * `CASSANDRA_RECONNECT_INTERVAL` (default `1m`) — reconnect interval to retry connecting to downed hosts
  * `CASSANDRA_MAX_RETRY_ATTEMPTS` (default `3`) — the number of attempts when reading from Cassandra

If you expect that Cassandra may not be available, you can try to increase the retry count or wait interval.

Example for using CLI arguments:

```yaml
collector:
  cmdlineParams:
    - '--cassandra.max-retry-attempts=10'
```

Example for using ENV variables:

```yaml
query:
  extraEnv:
    - name: CASSANDRA_RECONNECT_INTERVAL
      value: 2m
```

**Sources:**

* `docs/troubleshooting.superseded.md` — "gocql: no host available in the pool"
* [SimpleRetryPolicy — gocql](https://pkg.go.dev/github.com/gocql/gocql#SimpleRetryPolicy)

### `connection: no route to host`

**Symptoms:**

* In collector and query logs you can find the following logs:

  <!-- markdownlint-disable line-length -->
  ```text
  2023/08/18 09:41:46 gocql: unable to dial control conn 10.0.0.11:9042: dial tcp 10.0.0.11:9042: connect: no route to host
  2023/08/18 09:41:46 gocql: control unable to register events: dial tcp 10.0.0.11:9042: connect: no route to host
  2023/08/18 09:41:50 gocql: unable to dial control conn 10.0.0.12:9042: dial tcp 10.0.0.12:9042: connect: no route to host
  2023/08/18 09:41:53 gocql: unable to dial control conn 10.0.0.14:9042: dial tcp 10.0.0.14:9042: connect: no route to host
  2023/08/18 09:41:56 gocql: unable to dial control conn 10.0.0.11:9042: dial tcp 10.0.0.11:9042: connect: no route to host
  ```
  <!-- markdownlint-enable line-length -->

* Jaeger cannot restore the connection to Cassandra after a Cassandra node restarted, and does not recover on its own.

**Root cause:**

At start, Jaeger resolves the IP address of the Cassandra node by DNS service name. It also asks Cassandra about the
other nodes in the cluster and adds them to the pool. The IPs from this pool are used to connect during work.

Using IPs in the Cloud may lead to big problems if the Cassandra cluster is not stable and nodes restart regularly. For
example, with a single-node Cassandra, after restarting that node Jaeger loses the connection and can't restore it
without a Jaeger restart, because the resolved IP changed.

**How to check:**

1. Read the collector and query logs and confirm the dialed IPs no longer match the current Cassandra pod IPs.

   ```bash
   kubectl logs deployment/<release>-collector -n <namespace> | grep "no route to host"
   ```

2. List the current Cassandra pod IPs to compare against the IPs in the log.

   ```bash
   kubectl get pods -n <cassandra-namespace> -o wide
   ```

**How to fix:**

With a Cassandra cluster of 2 or more nodes restarted one by one — so that all nodes are never unavailable at once —
you should not face this issue.

With a single-node Cassandra, you can face these errors after restarting the Cassandra node.

1. **DANGEROUS — restarting interrupts trace ingestion and in-flight spans are lost until the new pods are ready.**
   Restart the Jaeger pods (collector and query) to return Jaeger to operable mode.

   ```bash
   kubectl rollout restart deployment/<release>-collector deployment/<release>-query -n <namespace>
   ```

**How to avoid this issue:**

**Note:** In some cases it may be useful to increase the reconnect interval and count for Cassandra as described in the
related problem, the case "`gocql: no hosts available in the pool`".

The platform Cassandra deployment uses a Service without load-balancing that has no Service IP, so Jaeger resolves
Cassandra pod IPs directly through the service DNS name.

To avoid this and resolve a Service IP that won't change after Cassandra's pods restart, create a new Service in the
Cassandra namespace, for example:

```yaml
kind: Service
apiVersion: v1
metadata:
  name: cassandra-lb
spec:
  ports:
    - name: icarus
      protocol: TCP
      port: 4567
      targetPort: 4567
    - name: cql-port
      protocol: TCP
      port: 9042
      targetPort: 9042
    - name: tcp-upd-port
      protocol: TCP
      port: 8778
      targetPort: 8778
    - name: reaper
      protocol: TCP
      port: 8080
      targetPort: 8080
  selector:
    service: cassandra-cluster
  type: ClusterIP
```

This Service has its own IP that won't change, and Jaeger will use it to connect. To configure Jaeger to use it, change
the `host` parameter:

```yaml
cassandraSchemaJob:
  host: cassandra-lb.<namespace>.svc
```

**Sources:**

* `docs/troubleshooting.superseded.md` — "connection: no route to host"

### Error reading `<name>` from storage: table `<name>` does not exist

**Symptoms:**

* In `collector` and `query` pod logs you usually see the following:

  ```text
  "error":"error reading operation_names from storage: table operation_names does not exist"
  ```

* Or:

  <!-- markdownlint-disable line-length -->
  ```text
  "query":"[query statement=\"INSERT INTO operation_names(service_name, operation_name) VALUES (?, ?)\" values=[app-service XHR /api/v1/orderManagement/salesOrder/123/bulkOperation] consistency=LOCAL_ONE]","error":"table operation_names does not exist"
  ```
  <!-- markdownlint-enable line-length -->

* **Note:** Table names and queries can be different.

**Root cause:**

The configured Cassandra has no necessary tables.

Jaeger has no logic that allows it to remove any tables or keyspaces in Cassandra, so this issue can occur only when
somebody manually dropped some tables, or executed another operation on Cassandra that led to removing Jaeger's tables.

Jaeger also has no logic to restore a keyspace or its tables at runtime. Jaeger's schema is initialized before it starts
during deployment, by a special Cassandra schema job.

**How to check:**

1. List the tables in Jaeger's keyspace and confirm the table named in the error is absent.

   ```bash
   cqlsh <cassandra-host> -u <username> -p <password> -e "DESCRIBE TABLES;" --keyspace <keyspace>
   ```

**How to fix:**

1. **DANGEROUS — redeploying restarts the collector and query pods, so trace ingestion stops until they are ready.**
   Redeploy Jaeger. All data that could be kept in Cassandra after any manual actions will be kept, because the schema
   job only creates missing tables and the store is not part of the release.

**How to avoid this issue:**

**Never** manually remove Jaeger's keyspace or any tables in Jaeger's keyspace, and do not execute any actions on
Cassandra that could lead to removing tables.

Also, if you used a Cassandra cluster with 3 or more nodes and want to scale it down to 1 node, you can't just remove or
disable two nodes in the cluster. It may lead to data loss, and to losing Jaeger's data. In this case you have to use
the Cassandra `nodetool` to remove some nodes from the cluster and re-balance data on the nodes.

**Sources:**

* `docs/troubleshooting.superseded.md` — "Error reading `<name>` from storage: table `<name>` does not exist"

### Cassandra TTL cannot be changed by an upgrade

**Symptoms:**

* Traces expire sooner or later than the TTL you now have configured.
* A changed `cassandraSchemaJob.ttl` value has no effect after an upgrade.

**Root cause:**

Cassandra Time To Live is set during keyspace creation, on the first Jaeger installation, and **can't be changed**
during the Jaeger upgrade procedure. The default is 172800 (2 days) for traces and 0 (no TTL) for dependencies.

**How to check:**

1. Read the TTL currently applied to Jaeger's tables and compare it with the value you configured.

   ```bash
   cqlsh <cassandra-host> -u <username> -p <password> -e "DESCRIBE TABLE <keyspace>.traces;"
   ```

**How to fix:**

To change the TTL after the keyspace has already been created, connect to Cassandra and change it manually.

1. Change the TTL for trace data. Existing rows keep the TTL they were written with; only newly written data uses the
   new value.

   ```sql
   USE jaegerkeyspace;

   ALTER TABLE traces                  WITH default_time_to_live = 86400;
   ALTER TABLE service_names           WITH default_time_to_live = 86400;
   ALTER TABLE operation_names_v2      WITH default_time_to_live = 86400;
   ALTER TABLE service_operation_index WITH default_time_to_live = 86400;
   ALTER TABLE service_name_index      WITH default_time_to_live = 86400;
   ALTER TABLE duration_index          WITH default_time_to_live = 86400;
   ALTER TABLE tag_index               WITH default_time_to_live = 86400;
   ```

2. Change the TTL for dependencies data.

   ```sql
   USE jaegerkeyspace;

   ALTER TABLE dependencies_v2 WITH default_time_to_live = 86400;
   ```

**How to avoid this issue:**

Set the correct TTL values on the first install:

```yaml
cassandraSchemaJob:
  ttl:
    trace: 172800s
    dependencies: 0
```

**Sources:**

* `docs/maintenance.md` — "Change Cassandra TTL"
* `docs/installation.md` — "**Warning!** TTL for Jaeger's Cassandra tables **can't be changed** during update!"

### Jaeger stops working after Cassandra is reinstalled or cleared

**Symptoms:**

* Jaeger stops working after Cassandra was reinstalled or cleared.
* Jaeger's keyspace no longer exists in Cassandra.

**Root cause:**

Reinstalling or clearing Cassandra removes the keyspace. The keyspace is required for Jaeger operation, and Jaeger does
not recreate it at runtime — the schema is created at deployment time.

**How to check:**

1. List the keyspaces and confirm Jaeger's keyspace is absent.

   ```bash
   cqlsh <cassandra-host> -u <username> -p <password> -e "DESCRIBE KEYSPACES;"
   ```

**How to fix:**

1. Run the upgrade job to recreate the keyspace. The keyspace will be recreated and Jaeger will work again.

   ```yaml
   cassandraSchemaJob:
     username: user
     password: password
   ```

**Sources:**

* `docs/maintenance.md` — "Cassandra is reinstalled"

### New Cassandra credentials are not picked up by running pods

**Symptoms:**

* The Cassandra user or password was changed, but Jaeger pods keep using the old credentials.
* Authentication errors continue after the secret was updated.

**Root cause:**

Jaeger reads the Cassandra credentials at startup. Changing them in values or in the `jaeger-cassandra` secret does not
affect already-running pods until they restart.

**How to check:**

1. Read the credentials currently stored in the secret and confirm they are the new ones.

   ```bash
   kubectl get secret jaeger-cassandra -n <namespace> -o jsonpath='{.data.username}' | base64 -d
   ```

**How to fix:**

1. Change the credentials by running the upgrade job with the new parameters.

   ```yaml
   jaeger:
     serviceName: jaeger
     storage:
       type: "cassandra"
   cassandraSchemaJob:
     password: newpassword
     username: newuser
   ```

   Alternatively, change the `jaeger-cassandra` secret manually. All the values in the secret must be encoded with
   base64. If you used an existing secret and the `cassandraSchemaJob.existingSecret` parameter when installing Jaeger,
   you have to edit the values in that secret manually.

2. **DANGEROUS — restarting interrupts trace ingestion and in-flight spans are lost until the new pods are ready.**
   Restart all Jaeger pods manually to apply the new Cassandra credentials.

**Sources:**

* `docs/maintenance.md` — "Change Cassandra User/Password"

## OpenSearch and Elasticsearch storage

Set `jaeger.storage.type: elasticsearch` for both OpenSearch and Elasticsearch — there is no `opensearch` value. See the
case "Collector crashes at startup after setting `jaeger.storage.type: opensearch`".

### Index cleaner runs successfully but deletes nothing, and disk keeps growing

**Symptoms:**

* Disk usage on OpenSearch or Elasticsearch grows without bound even though `elasticsearch.indexCleaner.install` is
  `true`.
* The index-cleaner CronJob completes successfully — it does not fail or crash.
* The cleaner log says it found nothing to remove:

  ```text
  No indices to delete
  ```

* Old `jaeger-span-*` indices remain in the store past `numberOfDays`.

**Root cause:**

The chart passes only connection settings to the index-cleaner, rollover, and lookback CronJobs: `ES_SERVER_URLS`,
`ES_USERNAME`, `ES_PASSWORD`, and the `ES_TLS_*` variables. It never passes `INDEX_PREFIX`, `ROLLOVER`, `ES_USE_ILM`,
`SHARDS`, `REPLICAS`, `UNIT`, or `CONDITIONS`.

The collector is configured separately: `elasticsearch.indexPrefix` is rendered into the collector's `jaeger_storage`
config as `index_prefix`. So the collector writes to `<prefix>-jaeger-span-*` while the cleaner, which received no
prefix, matches only unprefixed `jaeger-span-*`. It matches nothing, reports that there is nothing to delete, and exits
successfully.

Two configurations produce this same "cleaner deletes nothing" outcome:

1. `elasticsearch.indexPrefix` is set. The cleaner does not know the prefix.
2. `elasticsearch.useAliases: true` is set. Without `ROLLOVER=true` the cleaner expects date-suffixed daily indices
   (`-YYYY-MM-DD`), but rollover indices are sequence-numbered (`-000001`). The two naming schemes are mutually
   exclusive, so the cleaner matches nothing.

**How to check:**

1. Read the index-cleaner CronJob's environment and confirm no `INDEX_PREFIX` variable is present.

   ```bash
   kubectl get cronjob <release>-index-cleaner -n <namespace> -o yaml | grep -A20 env:
   ```

2. Read the most recent cleaner job's log and look for the `No indices to delete` line.

   ```bash
   kubectl logs -n <namespace> -l app.kubernetes.io/name=index-cleaner --tail=50
   ```

3. List the actual index names in the store and compare them against what the cleaner would match.

   ```bash
   curl -s -u '<username>:<password>' 'https://<opensearch-host>/_cat/indices?v'
   ```

**How to fix:**

1. Pass the prefix to the cleaner explicitly through `extraEnv`, using the same value as
   `elasticsearch.indexPrefix`, then upgrade the release. The variable is `INDEX_PREFIX`, not `ES_INDEX_PREFIX`.

   ```yaml
   elasticsearch:
     indexCleaner:
       extraEnv:
         - name: INDEX_PREFIX
           value: <your-prefix>
   ```

2. If you use rollover, tell the cleaner so, so it matches sequence-numbered indices instead of daily ones.

   ```yaml
   elasticsearch:
     indexCleaner:
       extraEnv:
         - name: ROLLOVER
           value: "true"
   ```

**How to avoid this issue:**

Whenever you set `elasticsearch.indexPrefix` or `elasticsearch.useAliases`, set the matching `extraEnv` on the
index-cleaner, rollover, and lookback CronJobs in the same change. The chart does not derive them for you, and a
mismatch fails silently rather than erroring.

**Data to collect:**

* `helm get values <release> -n <namespace>`.
* The index-cleaner CronJob YAML.
* The output of `_cat/indices`.
* The cleaner job logs.

**Sources:**

* `charts/qubership-jaeger/templates/opensearch/` — the CronJobs set only `ES_SERVER_URLS`, `ES_USERNAME`,
  `ES_PASSWORD`, and `ES_TLS_*`
* `charts/qubership-jaeger/templates/_helpers.tpl` — `index_prefix` is rendered into the collector config only
* [es-index-cleaner ignores the prefix — jaeger#4268](https://github.com/jaegertracing/jaeger/issues/4268)

### Traces disappear from the UI after one day although retention is set to more days

**Symptoms:**

* Traces older than about 24 hours cannot be found in the Jaeger UI.
* `elasticsearch.indexCleaner.numberOfDays` is set to a larger value, such as `7`, so longer retention is expected.
* The data is still present on disk — index sizes do not drop when the traces vanish from the UI.
* `elasticsearch.lookback.install` is `true`.

**Root cause:**

The lookback job removes old indices from the read alias, so they are no longer searched. Its defaults are `UNIT=days`
and `UNIT_COUNT=1`, and the chart passes neither, so lookback detaches everything older than one day from the read
alias.

The index cleaner's `numberOfDays` is a separate setting that controls deletion, not searchability. So the store keeps
seven days of data while the UI can only see one. Lookback only detaches aliases; it never deletes.

**How to check:**

1. Confirm the lookback CronJob is installed and read its environment — `UNIT` and `UNIT_COUNT` will be absent.

   ```bash
   kubectl get cronjob <release>-lookback -n <namespace> -o yaml | grep -A20 env:
   ```

2. Read which indices are currently attached to the read alias and compare against the indices that exist.

   ```bash
   curl -s -u '<username>:<password>' 'https://<opensearch-host>/_cat/aliases?v'
   ```

**How to fix:**

1. Set the lookback window explicitly through `extraEnv` so it matches your intended retention, then upgrade.

   ```yaml
   elasticsearch:
     lookback:
       extraEnv:
         - name: UNIT
           value: days
         - name: UNIT_COUNT
           value: "7"
   ```

2. Alternatively, if you do not need to shrink the read alias, disable lookback and let the index cleaner alone control
   retention.

   ```yaml
   elasticsearch:
     lookback:
       install: false
   ```

**How to avoid this issue:**

Pick one cleanup strategy. The repository states it plainly: **Warning!** Do not use Rollover (rollover and lookback)
and IndexCleaner together. Need to use only one cleanup strategy!

**Sources:**

* `docs/installation.md` — "Do not use Rollover (rollover and lookback) and IndexCleaner together."
* `charts/qubership-jaeger/templates/opensearch/lookback-cronjob.yaml` — no `UNIT` or `UNIT_COUNT` is passed

### `index_not_found_exception` after enabling rollover

**Symptoms:**

* The collector logs repeated errors naming a write alias that does not exist, such as `jaeger-span-write`, with
  `index_not_found_exception`.
* Spans are not saved, but the collector pod stays Running and its health endpoint reports healthy.
* `elasticsearch.rollover.install` is `true`.

**Root cause:**

`elasticsearch.rollover.install=true` only creates and manages rollover indices and aliases. The collector and query
must also be configured with `elasticsearch.useAliases=true`; otherwise they continue writing to daily indices and may
fail with `index_not_found_exception` if index auto-creation is disabled.

These are two separate settings, and the repository's own rollover example,
`docs/examples/opensearch/opensearch-rollover-values.yaml`, enables rollover without setting `useAliases`, which
reproduces this.

The rollover init job must create the aliases and templates before the collector and query start using them.

**How to check:**

1. Read whether both settings agree.

   ```bash
   helm get values <release> -n <namespace> | grep -E "useAliases|rollover" -A2
   ```

2. Check whether the write alias actually exists in the store.

   ```bash
   curl -s -u '<username>:<password>' 'https://<opensearch-host>/_cat/aliases?v'
   ```

3. Read the collector logs for the alias name in the error.

   ```bash
   kubectl logs deployment/<release>-collector -n <namespace> | grep index_not_found_exception
   ```

**How to fix:**

1. Enable alias usage so the collector and query write through the rollover aliases, then upgrade the release.

   ```yaml
   elasticsearch:
     useAliases: true
     rollover:
       install: true
   ```

2. If the aliases do not exist, confirm the rollover init job ran. It is a Helm pre-install hook, so it runs before the
   collector starts; re-running the install or upgrade runs it again.

**How to avoid this issue:**

Set `useAliases: true` and `rollover.install: true` together, in the same change. Enabling one without the other is
what produces this failure.

**Data to collect:**

* The collector logs showing the full bulk error.
* The output of `_cat/aliases` and `_cat/indices`.
* `helm get values <release> -n <namespace>`.

**Sources:**

* `charts/qubership-jaeger/values.yaml` — "`elasticsearch.rollover.install=true` only creates and manages rollover
  indices/aliases … otherwise they continue writing to daily indices and may fail with `index_not_found_exception`"
* [index_not_found_exception on write — jaeger#4851](https://github.com/jaegertracing/jaeger/issues/4851)

## Collector

### Collector refuses spans with `data refused due to high memory usage` while pod memory looks low

**Symptoms:**

* Clients fail to export spans and the collector logs a refusal:

  ```text
  data refused due to high memory usage
  ```

* A sending client or upstream collector reports the refusal as an HTTP 500 it treats as permanent:

  <!-- markdownlint-disable line-length -->
  ```text
  not retryable error: Permanent error: error exporting items, request to http://127.0.0.1:4320/v1/logs responded with HTTP Status Code 500, Message=data refused due to high memory usage
  ```
  <!-- markdownlint-enable line-length -->

* The collector logs `Memory usage is above soft limit. Refusing data` with a `cur_mem_mib` value far below the pod's
  memory limit.
* The pod is not close to being OOMKilled — container memory usage sits well under `collector.resources.limits.memory`.
* `collector.config.processors.memory_limiter.enabled` is `true`.

**Root cause:**

The memory limiter does not start refusing at `limit_mib`. It refuses at the **soft limit**, which is
`limit_mib - spike_limit_mib`. The chart's defaults are `limit_mib: 150` and `spike_limit_mib: 30`, so the collector
starts refusing spans at **120 MiB**.

The chart's default pod memory limit is `512Mi`, but the `values.yaml` comments size the limiter against a 200Mi pod:
"Default collector memory limit is 200Mi, so default is 150Mi (75% of 200Mi)". So enabling the limiter without also
tuning it makes the collector refuse data at roughly a quarter of the memory the pod is actually allowed to use.

Two further details matter when reading the numbers:

1. `cur_mem_mib` in the log is the Go heap (`runtime.MemStats.Alloc`), not the container RSS your dashboard shows. It
   will read lower than the pod's memory metric, and that gap is expected.
2. An oversized `spike_limit_mib` silently lowers the refusal point, because it is subtracted. It is not the trigger —
   it is the subtrahend.

**How to check:**

1. Read the configured limiter values and compute the soft limit as `limit_mib - spike_limit_mib`.

   ```bash
   kubectl get configmap <release>-collector -n <namespace> -o yaml | grep -A4 memory_limiter
   ```

2. Read the pod's memory limit and compare it against the soft limit from step 1.

   ```bash
   kubectl get deployment <release>-collector -n <namespace> -o jsonpath='{.spec.template.spec.containers[0].resources}'
   ```

3. Read the collector log for the refusal and note the reported `cur_mem_mib`.

   ```bash
   kubectl logs deployment/<release>-collector -n <namespace> | grep -i "memory"
   ```

**How to fix:**

1. Size the limiter against the pod's real memory limit. Set `limit_mib` to roughly 75-80% of the pod's memory limit
   and `spike_limit_mib` to roughly 15-20%, then upgrade. With the chart's default 512Mi pod:

   ```yaml
   collector:
     config:
       processors:
         memory_limiter:
           enabled: true
           limit_mib: 400
           spike_limit_mib: 100
   ```

2. If you raise the limiter, raise the pod's memory limit to match rather than leaving them inconsistent.

   ```yaml
   collector:
     resources:
       limits:
         memory: 2Gi
     config:
       processors:
         memory_limiter:
           limit_mib: 1600
           spike_limit_mib: 320
   ```

**How to avoid this issue:**

Whenever you enable or change `memory_limiter`, set `limit_mib` and `spike_limit_mib` from the pod's actual
`resources.limits.memory` in the same change — the repository's own guidance is that `limit_mib` should be about 75-80%
of the pod's memory limit. Do not rely on the defaults: they are sized for a 200Mi pod, while the chart ships 512Mi.

**Data to collect:**

* The rendered collector ConfigMap showing the `memory_limiter` block.
* The collector Deployment's `resources` block.
* Collector logs covering the refusals, including `cur_mem_mib`.

**Sources:**

* `charts/qubership-jaeger/values.yaml` — `limit_mib: 150`, `spike_limit_mib: 30`, and the 200Mi sizing comment
* `README.md` — "The memory limiter should be configured with `limit_mib` set to approximately 75-80% of the pod's
  memory limit"
<!-- markdownlint-disable line-length -->
* [memorylimiterprocessor — OpenTelemetry](https://github.com/open-telemetry/opentelemetry-collector/blob/main/processor/memorylimiterprocessor/README.md)
* [Memory above soft limit. Refusing data — collector#9043](https://github.com/open-telemetry/opentelemetry-collector/issues/9043)
* [Soft limit answered with HTTP 500 — collector#9636](https://github.com/open-telemetry/opentelemetry-collector/issues/9636)
<!-- markdownlint-enable line-length -->

### Spans are dropped and the collector logs `sending queue is full`

**Symptoms:**

* The collector logs a rejection naming the storage exporter:

  ```text
  Exporting failed. Rejecting data.
  ```

  with `"error": "sending queue is full"` and a `rejected_items` count.
* Spans are lost under load while the collector pod stays Running.
* The storage backend is slow, unreachable, or under-provisioned.

**Root cause:**

The collector hands spans to `jaeger_storage_exporter` through a queue. This chart configures it explicitly:
`queue.enabled: true`, `num_consumers: 100`, `queue_size: 1000`. When the storage backend cannot absorb writes as fast
as they arrive, the queue fills. Once full, new data is rejected rather than buffered, because overflow does not block.

The queue is a shock absorber for a slow backend, not a fix for one. A queue that fills repeatedly means the backend
cannot keep up with the span rate, or is failing writes that then consume retry capacity.

**How to check:**

1. Read the collector logs for the rejection and the `rejected_items` count.

   ```bash
   kubectl logs deployment/<release>-collector -n <namespace> | grep -i "queue is full"
   ```

2. Read the exporter metrics from the collector's metrics port. `otelcol_exporter_send_failed_spans_total` rising means
   writes to storage are failing; `otelcol_exporter_queue_size` approaching `otelcol_exporter_queue_capacity` means the
   queue is saturating.

   ```bash
   kubectl exec deployment/<release>-collector -n <namespace> -- wget -qO- http://localhost:8888/metrics | grep otelcol_exporter
   ```

3. Check the health of the storage backend itself — a full queue is usually a symptom of a slow or failing store.

**How to fix:**

1. Fix the storage backend first if `otelcol_exporter_send_failed_spans_total` is rising. Enlarging the queue in front
   of a failing store only delays the loss.
2. If the backend is healthy and the load is simply high, scale the collector horizontally. The repository's guidance is
   that increasing collector replicas proportionally increases Jaeger's ability to receive spans, as long as the store
   can receive them.

   ```yaml
   collector:
     replicas: 3
   ```

   Note that the chart's default affinity is a required pod anti-affinity per host, so replicas beyond the node count
   stay Pending — see the case "Collector or query pods stay Pending after increasing replicas".

3. Increase the queue only to absorb short bursts, not sustained overload.

   ```yaml
   collector:
     config:
       exporters:
         jaeger_storage_exporter:
           queue:
             queue_size: 5000
   ```

**How to avoid this issue:**

Size Cassandra or OpenSearch for the real span rate and watch `otelcol_exporter_send_failed_spans_total`. The
repository notes that increasing collector resources may not always result in more successfully processed spans —
Cassandra works better with parallel writes, so more collector replicas usually beats a bigger collector.

**Data to collect:**

* Collector logs showing the rejection lines and counts.
* The `otelcol_exporter_*` metrics from `:8888/metrics`.
* The storage backend's own health and logs for the same period.

**Sources:**

* `charts/qubership-jaeger/values.yaml` — `queue.enabled: true`, `num_consumers: 100`, `queue_size: 1000`
* `docs/performance.md` — collector scaling guidance
<!-- markdownlint-disable line-length -->
* [base_exporter.go — OpenTelemetry Collector](https://github.com/open-telemetry/opentelemetry-collector/blob/main/exporter/exporterhelper/internal/base_exporter.go)
* [sending_queue is full — contrib#9009](https://github.com/open-telemetry/opentelemetry-collector-contrib/issues/9009)
<!-- markdownlint-enable line-length -->

### Prometheus queries from the performance guide return no data

**Symptoms:**

* Grafana panels or alerts built on `jaeger_collector_queue_length`, `jaeger_collector_spans_dropped_total`, or
  `jaeger_collector_spans_received_total` show no data.
* Alerts on those metrics never fire, or break with a no-data error.
* The metrics are absent from the collector's `:8888/metrics` output.

**Root cause:**

Those are Jaeger **v1** metric names. This chart deploys Jaeger **v2**, which is built on the OpenTelemetry Collector
and does not define them. Upstream's own v1-to-v2 migration table lists `jaeger_collector_queue_length` and
`jaeger_collector_spans_dropped_total` with a v2 metric of `N/A` — they were not renamed, they no longer exist.

The guidance in `docs/performance.md` — including "the collector starts dropping spans if this metric reaches 2000" —
is v1 guidance. In v2 the equivalent queue belongs to the exporter, its size in this chart is `1000`, and overflow is
counted by `otelcol_exporter_enqueue_failed_spans_total` rather than by a dropped-spans counter.

**How to check:**

1. List the metrics the collector actually exposes and confirm the `jaeger_collector_*` names are absent while
   `otelcol_*` names are present.

   ```bash
   kubectl exec deployment/<release>-collector -n <namespace> -- wget -qO- http://localhost:8888/metrics | grep -c otelcol_
   ```

**How to fix:**

1. Rewrite the queries against the v2 metric names. On the Prometheus endpoint, counters carry a `_total` suffix and
   gauges do not.

   | Intent | Jaeger v2 metric |
   | --- | --- |
   | Spans received | `otelcol_receiver_accepted_spans_total` |
   | Spans rejected by a receiver | `otelcol_receiver_refused_spans_total` |
   | Spans written to storage | `otelcol_exporter_sent_spans_total` |
   | Failed writes to storage | `otelcol_exporter_send_failed_spans_total` |
   | Spans lost to a full queue | `otelcol_exporter_enqueue_failed_spans_total` |
   | Current queue depth | `otelcol_exporter_queue_size` |
   | Queue capacity | `otelcol_exporter_queue_capacity` |

2. For a healthy pipeline, compare the accepted and sent rates — they should rise together.

   ```text
   sum(rate(otelcol_receiver_accepted_spans_total[1m]))
   sum(rate(otelcol_exporter_sent_spans_total[1m]))
   ```

**How to avoid this issue:**

Treat any Jaeger runbook, dashboard, or alert citing `jaeger_collector_*` metrics or the "queue is 2000" threshold as
written for v1, and port it before relying on it here.

**Sources:**

* `docs/performance.md` — the v1 metric names and the 2000-queue guidance this case corrects
<!-- markdownlint-disable line-length -->
* [all-in-one metrics migration — Jaeger](https://github.com/jaegertracing/jaeger/blob/main/cmd/jaeger/docs/migration/all-in-one-metrics.md)
* [Troubleshooting — Jaeger v2 documentation](https://www.jaegertracing.io/docs/2.dev/operations/troubleshooting/)
<!-- markdownlint-enable line-length -->

### Collector or query pods stay Pending after increasing replicas

**Symptoms:**

* After raising `collector.replicas` or `query.replicas`, some pods stay `Pending` forever.
* `kubectl describe pod` reports that no nodes are available because of pod anti-affinity rules.
* The number of Running pods equals the number of schedulable nodes.

**Root cause:**

The chart's default affinity for both collector and query is a **required** pod anti-affinity on
`kubernetes.io/hostname`, so no two replicas of the same component may share a node. Because the rule is
`requiredDuringSchedulingIgnoredDuringExecution` rather than `preferred`, replicas beyond the node count cannot be
scheduled at all.

**How to check:**

1. Read why the pod cannot be scheduled.

   ```bash
   kubectl describe pod <pending-pod> -n <namespace>
   ```

2. Compare the replica count against the number of schedulable nodes.

   ```bash
   kubectl get nodes
   ```

**How to fix:**

1. Keep replicas at or below the node count. This preserves the fault tolerance the default is there to provide.
2. If you need more replicas than nodes and accept that several may share a node, override the affinity to a preferred
   rule.

   ```yaml
   collector:
     affinity:
       podAntiAffinity:
         preferredDuringSchedulingIgnoredDuringExecution:
           - weight: 100
             podAffinityTerm:
               labelSelector:
                 matchExpressions:
                   - key: app.kubernetes.io/name
                     operator: In
                     values:
                       - <collector-name>
               topologyKey: kubernetes.io/hostname
   ```

**How to avoid this issue:**

Scale replicas and nodes together, or switch to a preferred anti-affinity before scaling past the node count.

**Sources:**

* `charts/qubership-jaeger/values.yaml` — the default `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity for
  collector and query

## Readiness probe

### Collector and query pods restart in a loop while the storage backend is down

**Symptoms:**

* Collector and query pods restart repeatedly and show a climbing `RESTARTS` count in `kubectl get pods`.
* Events on the pod report `Liveness probe failed:` with an HTTP 500 from port 8080.
* The `probe` sidecar logs the failure:

  ```text
  Readiness probe failed
  ```

* For Cassandra, the sidecar also logs the failing query, for example:

  ```text
  Can't select from table. The error from server:
  ```

* The restarts began when Cassandra or OpenSearch became slow or unavailable, and Jaeger itself did not crash.

**Root cause:**

The chart injects a `probe` sidecar into the collector and query pods, and when `readinessProbe.install` is `true` —
the default — it also **rewires the pods' liveness probe** from Jaeger's own health endpoint (`/status` on port 13133)
onto the sidecar's `/health` on port 8080. The sidecar's health is the storage backend's health: it runs a real query
against Cassandra or a real HTTP GET against OpenSearch, and returns HTTP 500 when that fails.

So a storage outage makes the liveness probe fail, and per the Kubernetes documentation, "If a container fails its
liveness probe more times than the configured tolerance, the kubelet restarts that container." The pods restart while
the store is down, and keep restarting until it recovers — restarting Jaeger does not fix a store that is unavailable.

This is the failure mode the Kubernetes documentation warns about: "Incorrect implementation of liveness probes can lead
to cascading failures. This results in restarting of container under high load; failed client requests as your
application became less scalable; and increased workload on remaining pods due to some failed pods."

A readiness failure alone would be the proportionate response: the Pod's IP is removed from the Service's EndpointSlices
and no traffic is sent to it, without a restart.

**How to check:**

1. Read the restart count and the pod events naming the failing probe.

   ```bash
   kubectl get pods -n <namespace>
   kubectl describe pod <collector-pod> -n <namespace>
   ```

2. Read the `probe` sidecar's logs to see which backend check is failing and why.

   ```bash
   kubectl logs <collector-pod> -n <namespace> -c probe
   ```

3. Confirm which endpoint the liveness probe currently targets. Port 8080 is the sidecar; port 13133 is Jaeger's own.

   ```bash
   kubectl get deployment <release>-collector -n <namespace> -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}'
   ```

4. Check whether the storage backend is actually healthy — the restarts are a symptom, not the cause.

**How to fix:**

1. Fix the storage backend. While Cassandra or OpenSearch is unavailable the restarts will continue, and no Jaeger-side
   change makes traces flow again.
2. To stop the restart loop from compounding the outage, disable the custom probe so liveness returns to Jaeger's own
   health endpoint, which does not depend on storage.

   ```yaml
   readinessProbe:
     install: false
   ```

   The trade-off is explicit: the pods then stay Ready during a storage outage and are not removed from the Service, but
   they also stop restart-looping.

3. If you keep the probe, give it more tolerance so brief storage blips do not trigger restarts.

   ```yaml
   readinessProbe:
     periodSeconds: 30
     timeoutSeconds: 10
     retries: 10
     errors: 10
   ```

**How to avoid this issue:**

Decide deliberately whether a storage outage should restart Jaeger. Jaeger's own `/status` endpoint on port 13133 is a
dependency-free liveness target and reports healthy even when the store is down, which is what a liveness probe should
check — that the process itself is alive rather than that its dependency is reachable.

**Data to collect:**

* `kubectl describe pod` for a restarting collector or query pod, showing the probe failure events.
* The `probe` container's logs.
* The storage backend's health and logs for the same period.

**Sources:**

* `charts/qubership-jaeger/templates/collector/deployment.yaml` — the liveness probe targets `/health:8080` when
  `readinessProbe.install` is true, and `/status` otherwise
* `readiness-probe/main.go` — `Readiness probe failed`, returned with HTTP 500
<!-- markdownlint-disable line-length -->
* [Liveness and readiness probes — Kubernetes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/)
<!-- markdownlint-enable line-length -->

## Query and Envoy auth proxy

The auth proxy is an Envoy sidecar in the query pod, enabled with `proxy.install: true`. It implements basic auth with
an inline Lua script rather than Envoy's `basic_auth` filter, and OAuth2 with Envoy's `oauth2` filter. Enabling it
repoints the Service's port 16686 to the Envoy listener on 16688.

### Jaeger UI opens without asking for credentials

**Symptoms:**

* The Jaeger UI loads for anyone who has the URL — no login prompt, no `401`.
* `proxy.install` is `true` and `proxy.type` is `basic`, so a login was expected.
* The Envoy container logs a Lua error while requests still return 200:

  ```text
  script log: [string "function envoy_on_request(request_handle)..."]:2: bad argument #1 to 'pairs' (value expected)
  ```

* The Envoy admin stat `.lua.errors` increases as requests arrive.

**Root cause:**

Basic auth is implemented as an inline Lua script that iterates the credentials attached as route metadata:

```lua
for _, credential in pairs(request_handle:metadata():get("credentials")) do
```

If that metadata resolves to nil — because the filter `name:` and the `filter_metadata:` key no longer match, or because
`proxy.basic.users` rendered empty — then `pairs(nil)` raises a Lua error. Envoy's Lua filter treats a script error as a
counter increment and a log line: it does not send a local reply, so the filter chain continues and the request reaches
the Jaeger UI unauthenticated.

The script only denies a request by reaching its final `request_handle:respond(...401...)`. A script that throws before
that point never denies anything, so this authentication filter **fails open**.

**How to check:**

1. Request the UI with no credentials and read only the status code. Anything other than `401` means the proxy is not
   authenticating.

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' http://<query-service>:16686/
   ```

2. Read the rendered Envoy config and confirm the filter name and the metadata key are byte-identical — both must be
   `envoy.filters.http.lua`.

   ```bash
   kubectl get secret proxy-config -n <namespace> -o jsonpath='{.data.config\.yaml}' | base64 -d
   ```

3. Read the Envoy container logs for the Lua error.

   ```bash
   kubectl logs <query-pod> -n <namespace> -c proxy | grep "script log:"
   ```

4. Read the Lua stats from the Envoy admin endpoint. A non-zero `.lua.errors` means scripts are throwing.

   ```bash
   kubectl exec <query-pod> -n <namespace> -c proxy -- curl -s localhost:9901/stats | grep '\.lua\.errors'
   ```

**How to fix:**

1. Confirm `proxy.basic.users` is a non-empty list of base64 `login:password` entries, then upgrade the release so the
   metadata is populated.

   ```yaml
   proxy:
     install: true
     type: basic
     basic:
       users:
         - <base64-of-user:password>
   ```

2. **DANGEROUS — while the UI is unauthenticated, anyone who can reach the Service can read every trace. Treat the
   exposure as ongoing until the check in step 1 returns `401`.** Until the proxy denies correctly, restrict access to
   the query Service by other means — remove the Ingress or Route that publishes it, or apply a NetworkPolicy — rather
   than leaving it reachable.

**How to avoid this issue:**

After enabling or changing the proxy, always verify with an unauthenticated request that the answer is `401`. Do not
infer that authentication works from the fact that a correct password succeeds — a failing-open filter accepts both.

**Data to collect:**

* The decoded `proxy-config` secret.
* Envoy container logs containing `script log:` lines.
* The `.lua.errors` and `.lua.executions` stats.
* The status code of an unauthenticated request.

**Sources:**

* `charts/qubership-jaeger/templates/query/auth-proxy/proxy-secret-config.yaml` — the inline Lua script
* [Lua filter — Envoy](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/lua_filter)
* [Running Lua filter as fail closed — envoyproxy/envoy#14980](https://github.com/envoyproxy/envoy/issues/14980)

### Basic auth rejects credentials that are known to be correct

**Symptoms:**

* The browser prompts for a password again and again, and a password known to be correct is not accepted.
* Requests return `HTTP/1.1 401 Unauthorized` with `www-authenticate: Basic realm="Unknown"`.
* A `401` followed by a `200` is the normal flow; a `401` followed by another `401` with a good password is this
  failure.

**Root cause:**

The Lua script compares the whole `authorization` header against each configured credential with an exact string
comparison. Two things break that comparison:

1. **A trailing newline in the base64 value.** `echo "admin:admin" | base64` appends a newline before encoding and
   yields `YWRtaW46YWRtaW4K`, while `echo -n "admin:admin" | base64` yields `YWRtaW46YWRtaW4=`. The extra byte makes
   the comparison fail while the value looks correct.
2. **The scheme's capitalization.** The comparison is byte-exact, so a client that sends `BASIC` instead of `Basic` is
   rejected even though the HTTP specification matches the scheme case-insensitively.

**How to check:**

1. Decode the configured credential and look for a trailing `0a` byte.

   ```bash
   kubectl get secret proxy-config -n <namespace> -o jsonpath='{.data.config\.yaml}' | base64 -d | grep -A3 credentials
   ```

2. Decode a single configured user value and inspect its final byte.

   ```bash
   echo -n '<configured-base64-value>' | base64 -d | xxd | tail -1
   ```

**How to fix:**

1. Regenerate the credential without a trailing newline and upgrade the release.

   ```bash
   printf '%s' '<user>:<password>' | base64
   ```

   ```yaml
   proxy:
     basic:
       users:
         - <regenerated-base64-value>
   ```

**How to avoid this issue:**

Always encode with `echo -n` or `printf`, as `docs/examples/auth.md` shows. The failure is one keystroke away and the
resulting value looks correct.

**Sources:**

* `charts/qubership-jaeger/templates/query/auth-proxy/proxy-secret-config.yaml` — the exact-match comparison
* `docs/examples/auth.md` — "echo -n "admin:admin" | base64"
* [RFC 7617 — The 'Basic' HTTP Authentication Scheme](https://datatracker.ietf.org/doc/html/rfc7617)

### Every user is logged out of the UI after each Helm upgrade

**Symptoms:**

* After every `helm upgrade`, all users are bounced back to the identity provider and must log in again.
* The login page keeps redirecting, and clearing cookies does not survive the next upgrade.
* The identity provider logs a burst of successful logins right after an upgrade.
* `proxy.type` is `oauth2`.

**Root cause:**

The chart renders the OAuth2 HMAC secret with `randAlphaNum 32`, which produces a **new random value on every render**.
Each `helm upgrade` therefore writes a different HMAC secret into the `oauth2-token` secret. Envoy signs its session
cookie with that value, so after an upgrade it cannot validate any cookie it issued before, treats every session as
unauthenticated, and restarts the login flow.

**How to check:**

1. Read the HMAC secret currently stored in the cluster and note it.

   ```bash
   kubectl get secret oauth2-token -n <namespace> -o yaml
   ```

2. Render the chart again without applying it and compare the HMAC value against the stored one. A different value on
   every render confirms the drift.

   ```bash
   helm template <release> <chart> -n <namespace> -f <your-values.yaml> | grep -A3 inline_bytes
   ```

**How to fix:**

1. **DANGEROUS — changing the HMAC secret invalidates every active session, so all users are logged out once when the
   new value is applied.** Pin the HMAC secret to a fixed value you supply, so upgrades stop rotating it. Store the
   value like any other credential.

**How to avoid this issue:**

Pin the secret before an upgrade you do not want to interrupt users, rather than after. As shipped, every upgrade
rotates it.

**Sources:**

* `charts/qubership-jaeger/templates/query/auth-proxy/proxy-secret-oauth-token.yaml` — `randAlphaNum 32`
* [OAuth2 filter — Envoy](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/oauth2_filter)

### OAuth2 login loops forever when the UI is reached over plain HTTP

**Symptoms:**

* The browser bounces between Jaeger and the identity provider and never lands on the UI.
* The browser reports `ERR_TOO_MANY_REDIRECTS`.
* No error appears in the Envoy log.
* The session cookie is never stored, although the response carries a `Set-Cookie`.
* The UI is being reached over `http://`, not `https://`.

**Root cause:**

Envoy's OAuth2 filter sets its session cookies with the `Secure` attribute, so a browser on a plain HTTP origin
discards them. Without the cookie, the next request is unauthenticated and the filter starts the flow again — forever.

The chart also hardcodes the callback as `redirect_uri: "https://%REQ(:authority)%/callback"`, so the flow assumes
HTTPS regardless of how the browser actually reached the UI.

**How to check:**

1. Confirm the scheme in the browser's address bar is `https://`.
2. In the browser's developer tools, look for a `Set-Cookie` on the redirect response and check whether the cookie is
   stored afterward. A `Secure` cookie on an HTTP origin is dropped.
3. Read the rendered Envoy config and note the `redirect_uri`.

   ```bash
   kubectl get secret proxy-config -n <namespace> -o jsonpath='{.data.config\.yaml}' | base64 -d | grep redirect_uri
   ```

**How to fix:**

1. Terminate TLS in front of Jaeger so the browser reaches the UI over HTTPS, which is what the filter requires. The
   repository does not support TLS between the browser and the UI directly — terminate it at the ingress.

**How to avoid this issue:**

Publish the query UI over HTTPS whenever `proxy.type: oauth2` is used. The `values.yaml` examples show `http://`
identity-provider URLs, which invites a mixed setup that reproduces this.

**Sources:**

* `charts/qubership-jaeger/templates/query/auth-proxy/proxy-secret-config.yaml` — the hardcoded `https://` callback
* [OAuth2 filter — Envoy](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/oauth2_filter)

### OAuth2 login fails and the identity provider reports an invalid redirect URI

**Symptoms:**

* The identity provider shows an error page instead of a login form, for example Keycloak's
  `Invalid parameter: redirect_uri`.
* The identity provider's event log records `error=invalid_redirect_uri`.
* Login never returns to Jaeger.

**Root cause:**

Envoy sends the callback the chart renders — `https://<authority>/callback` — and the identity provider only accepts a
redirect URI that it has registered. Keycloak compares valid redirect URIs with exact string matching, so the scheme,
host, port, and path must all match, and recent versions no longer accept wildcards for the hostname.

Because the chart hardcodes `https://` in the callback, a Jaeger published over HTTP produces a callback the provider
was never given.

**How to check:**

1. Read the exact callback Envoy will send.

   ```bash
   kubectl get secret proxy-config -n <namespace> -o jsonpath='{.data.config\.yaml}' | base64 -d | grep redirect_uri
   ```

2. In the identity provider, read the client's registered redirect URIs and compare them character by character against
   `https://<your-jaeger-host>/callback`.
3. Read the identity provider's event log for `invalid_redirect_uri`.

**How to fix:**

1. Register the exact callback URI on the identity-provider client — `https://<your-jaeger-host>/callback`. This is a
   change on the identity provider, not in the chart. Avoid a bare wildcard.

**Sources:**

* `charts/qubership-jaeger/templates/query/auth-proxy/proxy-secret-config.yaml` — the rendered callback
* [Upgrading Guide — Keycloak](https://www.keycloak.org/docs/latest/upgrading/index.html)

### OAuth2 login fails after enabling TLS on the identity provider

**Symptoms:**

* Login fails after the callback, and Envoy reports a generic OAuth flow failure.
* Envoy logs an upstream connection failure to the identity provider, such as
  `upstream connect error or disconnect/reset before headers`.
* The access log shows the `UF` or `UH` response flag for the `auth` cluster.
* The identity-provider endpoints are `https://` while `proxy.oauth2.idpPort` is `80`.

**Root cause:**

Two settings decide how Envoy reaches the identity provider, and neither follows the token endpoint:

1. `proxy.oauth2.idpPort` is set independently of the endpoint scheme. The repository's own example,
   `docs/examples/auth/oauth2-values.yaml`, pairs `https://` endpoints with `idpPort: 80`, so Envoy connects to the
   plaintext port of a TLS provider.
2. The TLS transport socket is attached to the `auth` cluster only when **`authorizationEndpoint`** starts with
   `https://` — but that cluster carries **`tokenEndpoint`** traffic. An HTTPS token endpoint combined with an HTTP
   authorization endpoint makes Envoy speak plaintext to a TLS port.

**How to check:**

1. Read the configured endpoints and port together, and check that the port matches the token endpoint's scheme — 443
   for `https://`, 80 for `http://`.

   ```bash
   helm get values <release> -n <namespace> | grep -A8 oauth2
   ```

2. Read the `auth` cluster from the Envoy admin endpoint and look at its connection failure counters.

   ```bash
   kubectl exec <query-pod> -n <namespace> -c proxy -- curl -s localhost:9901/clusters | grep '^auth'
   ```

3. Read the rendered config and check whether the `auth` cluster has a `transport_socket` at all.

   ```bash
   kubectl get secret proxy-config -n <namespace> -o jsonpath='{.data.config\.yaml}' | base64 -d | grep -A5 transport_socket
   ```

**How to fix:**

1. Set `idpPort` from the token endpoint's scheme, and keep both endpoints on the same scheme so the TLS decision
   matches the traffic.

   ```yaml
   proxy:
     oauth2:
       tokenEndpoint: https://<idp-host>/realms/<realm>/protocol/openid-connect/token
       authorizationEndpoint: https://<idp-host>/realms/<realm>/protocol/openid-connect/auth
       idpAddress: <idp-host>
       idpPort: 443
   ```

**How to avoid this issue:**

Do not copy `idpPort` from the shipped example without checking it — as written it pairs HTTPS endpoints with port 80.
Keep `tokenEndpoint` and `authorizationEndpoint` on the same scheme.

**Data to collect:**

* `helm get values <release> -n <namespace>` for the `proxy` block.
* The `auth` cluster stats from the Envoy admin endpoint.
* Envoy container logs from the failed login.

**Sources:**

* `charts/qubership-jaeger/templates/query/auth-proxy/proxy-secret-config.yaml` — the TLS condition keyed on
  `authorizationEndpoint`
* `docs/examples/auth/oauth2-values.yaml` — `https://` endpoints with `idpPort: 80`
* [Service discovery](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/upstream/service_discovery)

### Jaeger UI returns 503 after a successful login

**Symptoms:**

* Authentication succeeds, then the UI shows a 503 and Envoy returns:

  <!-- markdownlint-disable line-length -->
  ```text
  upstream connect error or disconnect/reset before headers. reset reason: remote connection failure, transport failure reason: delayed connect error: Connection refused
  ```
  <!-- markdownlint-enable line-length -->

* The access log shows the `UF` or `UH` response flag.
* The query pod reports Ready even while the UI returns 503.

**Root cause:**

Envoy proxies to the `jaeger-query` container inside the same pod. Envoy is up and answering as soon as its own
listener is ready, while the query container may still be starting or may have crashed. The proxy's readiness reflects
Envoy, not Jaeger, so the pod can be Ready and still serve 503.

**How to check:**

1. Read the upstream cluster's health and connection-failure counters from the Envoy admin endpoint.

   ```bash
   kubectl exec <query-pod> -n <namespace> -c proxy -- curl -s localhost:9901/clusters | grep upstream-service
   ```

2. Read the query container's own logs to find out why it is not serving.

   ```bash
   kubectl logs <query-pod> -n <namespace> -c jaeger-query
   ```

**How to fix:**

1. Fix whatever prevents the query container from serving — most often it cannot reach the storage backend. The 503
   from Envoy is a symptom of the upstream, not of the proxy.

**Data to collect:**

* The `upstream-service` cluster stats.
* The `jaeger-query` container logs.
* The Envoy access log lines with their response flags.

**Sources:**

<!-- markdownlint-disable line-length -->
* [Access logging response flags — Envoy](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage)
<!-- markdownlint-enable line-length -->

### Query pod crash-loops with an Envoy configuration error

**Symptoms:**

* The query pod is in `CrashLoopBackOff` and the `proxy` container exits at startup.
* The Envoy container logs one of:

  <!-- markdownlint-disable line-length -->
  ```text
  error initializing configuration '/envoy/config.yaml': paths must refer to an existing path in the system: '/envoy/oauth2/token-secret.yaml' does not exist
  ```

  ```text
  error initializing configuration '/envoy/config.yaml': GenericSecretSdsApi: node 'id' and 'cluster' are required. Set it either in 'node' config or via --service-node and --service-cluster options.
  ```
  <!-- markdownlint-enable line-length -->

* The UI is unreachable on port 16686.

**Root cause:**

Two startup requirements of the OAuth2 configuration:

1. Envoy reads the OAuth2 token from a file at startup. If the `oauth2-token` secret is not mounted, the path does not
   exist and Envoy refuses to start.
2. The OAuth2 bootstrap has no `node` block, so it relies entirely on the container's `--service-cluster envoy` and
   `--service-node envoy` arguments to satisfy the secret discovery service's node requirement. Overriding the
   container arguments removes them and Envoy exits immediately.

**How to check:**

1. Read the previous container's logs to see the startup error.

   ```bash
   kubectl logs <query-pod> -n <namespace> -c proxy --previous
   ```

2. Confirm the secret exists and is mounted.

   ```bash
   kubectl get secret oauth2-token -n <namespace>
   kubectl exec <query-pod> -n <namespace> -c proxy -- ls -la /envoy/oauth2/
   ```

**How to fix:**

1. If the secret is missing, re-run the install or upgrade so the chart creates it. The chart generates `oauth2-token`
   when `proxy.type` is `oauth2`.
2. If the container arguments were overridden, restore `--service-cluster envoy` and `--service-node envoy`, which the
   configuration depends on.

**Data to collect:**

* The `proxy` container's previous logs.
* The list of secrets in the namespace.
* The query Deployment's `args` for the proxy container.

**Sources:**

* `charts/qubership-jaeger/templates/query/auth-proxy/` — the OAuth2 bootstrap and token secret
* [Secret discovery service — Envoy](https://www.envoyproxy.io/docs/envoy/latest/configuration/security/secret)

### Security defaults of the auth proxy

This section is background rather than a failure. Review these before publishing the UI, because each is live in the
chart's defaults.

* **The default credentials are public.** `proxy.basic.users` ships `YWRtaW46YWRtaW4=` and `dGVzdDp0ZXN0`, which decode
  to `admin:admin` and `test:test`; base64 is encoding, not encryption. Installing with `proxy.install: true` and
  `proxy.type: basic` without overriding `users` gives a login that anyone can guess. Always set your own list.
* **The Envoy admin port is published.** When the proxy is enabled, the query Service exposes port 9901 alongside the
  UI, and the admin interface has no authentication. Envoy's documentation states that the admin interface "allows
  destructive operations to be performed" and that it "is critical that access to the administration interface is only
  allowed via a secure network". Anyone who can reach the Service can read the full configuration, including
  configured credentials, or shut Envoy down. Restrict access to this port.
* **Envoy runs as root.** The chart sets `ENVOY_UID` and `ENVOY_GID` to `0`, overriding the image's non-root default.
  Envoy's documentation notes that running as root "has the potential to weaken the security of your running
  container".
* **The identity provider's certificate is not verified.** The `auth` cluster's TLS context sets only `sni` and no
  validation context. Per Envoy's documentation, certificate verification is not enabled unless the validation context
  specifies trusted authority certificates — so the token exchange is not protected against an interposed server.
* **The chart implements no user or group authorization.** `docs/examples/auth.md` documents `oauth2.issuerUrl`,
  `oauth2.allowedUsers`, and `oauth2.allowedGroups`, but the chart has none of those keys — the real ones are
  `tokenEndpoint`, `authorizationEndpoint`, `clientId`, `clientToken`, `idpAddress`, and `idpPort`. Any user who can
  authenticate against the configured realm reaches the UI. Do not rely on that document's allow-lists: they do
  nothing.

**Sources:**

* `charts/qubership-jaeger/values.yaml` — the default `users` list
* `charts/qubership-jaeger/templates/query/service.yaml` — the published `envoy-admin` port
* `charts/qubership-jaeger/templates/query/deployment.yaml` — `ENVOY_UID`/`ENVOY_GID` set to `0`
* [Administration interface — Envoy](https://www.envoyproxy.io/docs/envoy/latest/operations/admin)
* [Docker image options — Envoy](https://www.envoyproxy.io/docs/envoy/latest/start/docker)
