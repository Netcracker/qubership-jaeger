# Troubleshooting

This section describes in detail some failover scenarios.

## Deployment Issues

### Jaeger collector, query, cassandra schema job can't start/failed

If the `Jaeger` cassandra schema job fails to complete, with different errors related to the Cassandra connection,
the issue may be related to connection issues or problems with Cassandra.

**Solution:**

Check the following:

* Cassandra connection string is valid, and Cassandra running and operable
* Cassandra's `user` and `password` are valid
* Cassandra `datacenter` is valid for you Cassandra cluster
* Keyspace can be created in Cassandra
* You configure TLS parameters if TLS enabled and required for Cassandra
* Cassandra must have at least 2 nodes (better >= 3 nodes) if Jaeger is installed in the `prod` mode

View the errors from the Cassandra logs if they exist.


### no matches for kind "Ingress" in version "networking.k8s.io/v1beta1"

We are using Helm to deploy Jaeger. Helm tracks all resources that it created in special secrets with names:

```bash
sh.helm.release.<version>.<name>.<version>
```

In this secret, it stores all objects that it created or updated during the previous deployment.

Before upgrading to the new version Helm always checks already existing objects in your Cloud.
Because previously Helm created Ingress with API version:

```bash
networking.k8s.io/v1beta1
```

it wants to get this object from Kubernetes.

Since the Kubernetes 1.22 team who develop Kubernetes removed a lot of deprecated APIs:
[https://kubernetes.io/docs/reference/using-api/deprecation-guide/#v1-22](https://kubernetes.io/docs/reference/using-api/deprecation-guide/#v1-22)

And particularly old Ingresses APIs
[https://kubernetes.io/docs/reference/using-api/deprecation-guide/#ingress-v122](https://kubernetes.io/docs/reference/using-api/deprecation-guide/#ingress-v122)

You can face this issue in the case if you first upgrade Kubernetes to version >= 1.22
and only next want to upgrade Jaeger deployment. Helm wants to get an object for the old API which
already doesn't exist in Kubernetes and failed.

**Solution:**

If the service doesn't support migration by APIs or you already made a mistake and upgraded Kubernetes,
you have only two options:

* Make a clean install of Jaeger
* Remove all secrets with names:

    ```bash
    sh.helm.release.<version>.<name>.<version>
    ```

**How to avoid this issue:**

If services support migration to new Kubernetes the correct way to upgrade it is:

1. Before upgrading Kubernetes, need to upgrade the Service to the new version which can work in the new Kubernetes
2. Only after it upgrades Kubernetes to the new version


### Labels and Annotations validation error

Helm doesn't allow a resource to be owned by more than one deployment. During jaeger upgrade it's possible you create
resources that already existed and created outside of Helm. In such cases you may see error related to labels and
annotation validation. For more details please refer
[article](https://stackoverflow.com/questions/62964532/helm-not-creating-the-resources)

**Solution**

To add and use correct values for following labels and annotations:

```yaml
labels:
  app.kubernetes.io/managed-by: Helm
annotations:
  meta.helm.sh/release-name: <RELEASE_NAME>
  meta.helm.sh/release-namespace: <RELEASE_NAMESPACE>
```

This solution is proposed in [document](https://github.com/helm/helm/pull/7649)


## Runtime Issues

### Jaeger lost connection to Cassandra after Cassandra's restart

Now we know about the two most often issues related to Cassandra's connections. Both issues and ways to solve them
are described above.

#### gocql: no host available in the pool

Jaeger during the use of Cassandra as a storage has by default used a
[SimpleRetryPolicy](https://pkg.go.dev/github.com/gocql/gocql#SimpleRetryPolicy) from the Gocql module.
It means that when Jaeger can't execute a query, it will retry the query with the following rules:

* Will retry the specified number of retries
* Will wait the specified time between retries

By default, Jaeger will do `3` retries and wait `1m` between retries. So total it will retry `3 minutes`.
If Jaeger can't successfully retry the query for `3 minutes` it will mark Cassandra's host as not available and
won't use next.

As a typical symptom of this issue, in collector and query logs (or even in Query UI) you can find the following logs:

```yaml
error reading service_names from storage: gocql: no hosts available in the pool
...
```

**Solution:**

You have to execute the following steps:

* Verify that Cassandra is available and operable now
* Restart the collector and query pods

**How to avoid this issue:**

**Warning!** Before you execute the steps below, please read about the next problem in the section
[connection: no route to host](#connection-no-route-to-host) and apply a solution for the described problem.
In cases of using Cassandra cluster with one node, its **IP always will be changed** after Cassandra's restart.
Even in cases of using Cassandra cluster with 3 or more nodes might occur a situation when all nodes
can restart and change their IPs.

The values of the retry count and wait interval can be specified using the CLI arguments or ENV variables:

* CLI arguments
  * `--cassandra.reconnect-interval` (default `1m`) - Reconnect interval to retry connecting to downed hosts
  * `--cassandra.max-retry-attempts` (default `3`) - The number of attempts when reading from Cassandra
* ENV variable
  * `CASSANDRA_RECONNECT_INTERVAL` (default `1m`) - Reconnect interval to retry connecting to downed hosts
  * `CASSANDRA_MAX_RETRY_ATTEMPTS` (default `3`) - The number of attempts when reading from Cassandra

If you expect that Cassandra may not be available, you can try to increase the retry count or wait interval.

For example, you can specify these parameters as follows:

```yaml
## Example for using CLI arguments
collector:
  cmdlineParams:
    - '--cassandra.max-retry-attempts=10'

## Example for using ENV variables
query:
  extraEnv:
    - name: CASSANDRA_RECONNECT_INTERVAL
      value: 2m
```


#### connection: no route to host

Now Jaeger during start resolving the IP address of the Cassandra node by DNS service name. Also Jaeger during the start
ask Cassandra about other nodes in the Cassandra cluster and add them to the pool. IPs from this pool will be used to
connect to the cluster during work.

Obviously in the Cloud using IPs may lead to big problems if Cassandra's cluster is not stable and nodes regularly
restart (for any reason).

For example, if you are using a Cassandra with only one node, after restarting this node Jaeger will lose connection
with it and can't restore it without Jaeger's restart. It may occur because Jaeger will resolve the IP of
the Cassandra node, but after restart this IP will change.

As a typical symptom of this issue, in collector and query logs you can find the following logs:

```bash
2023/08/18 09:41:46 gocql: unable to dial control conn 10.0.0.11:9042: dial tcp 10.0.0.11:9042: connect: no route to host
2023/08/18 09:41:46 gocql: control unable to register events: dial tcp 10.0.0.11:9042: connect: no route to host
2023/08/18 09:41:50 gocql: unable to dial control conn 10.0.0.12:9042: dial tcp 10.0.0.12:9042: connect: no route to host
2023/08/18 09:41:53 gocql: unable to dial control conn 10.0.0.14:9042: dial tcp 10.0.0.14:9042: connect: no route to host
2023/08/18 09:41:56 gocql: unable to dial control conn 10.0.0.11:9042: dial tcp 10.0.0.11:9042: connect: no route to host
...
```

**Solution:**

If you are using a Cassandra cluster from 2 or more nodes and will restart nodes one by one
(i.e. all nodes never will be unavailable) you should face such an issue.

If you are using a Cassandra with only 1 node, you can face such errors after restarting the Cassandra node.
In this case, you have to restart Jaeger pods (collector and query) to return Jaeger to operable mode.

**How to avoid this issue with one Cassandra node:**

**Note:** In some cases may be useful to increase the reconnect interval and count for Cassandra as described in related
problem [gocql: no host available in the pool](#gocql-no-host-available-in-the-pool).

Now platform Cassandra deployment uses a Service without load-balancing and which has no Service IP. So Jaeger
using the service DNS name will directly resolve Cassandra pod IPs.

To avoid it and resolve Service IP (that won't change after Cassandra's pods restart) you can create a new Service
in the Cassandra namespace.

For example, using the following Service YAML manifest:

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

This Service will have its own IP that won't change and that will use Jaeger to connect.

To configure Jaeger use it needs to change `host` parameter:

```yaml
cassandraSchemaJob:
  host: cassandra-lb.<namespace>.svc
```


### Error reading `<name>` from storage: table `<name>` does not exist

For this error, you usually can see in `collector` and `query` pods logs as follows:

```bash
"error":"error reading operation_names from storage: table operation_names does not exist"
```

or

```bash
"query":"[query statement=\"INSERT INTO operation_names(service_name, operation_name) VALUES (?, ?)\" values=[app-service XHR /api/v1/orderManagement/salesOrder/123/bulkOperation] consistency=LOCAL_ONE]","error":"table operation_names does not exist"
```

**Note:** Table names and queries can be different.

It means that the configured Cassandra has no necessary tables.

Jaeger has no logic that allows it to remove any tables or keyspaces in Cassandra. So this issue can occur only
in cases when somebody manually dropped some tables or executed any other operations with Cassandra that led
to removing any tables in Jaeger.

Also, Jaeger has no logic to restore keyspace or its tables in runtime. Jaeger's schema initializes before it starts
during deployment. It has a special Cassandra schema job to create its schemas in Cassandra.

**Solution:**

**How to avoid this issue:**

You have to redeploy Jaeger. All data, that could be kept in Cassandra after any manual actions, will be kept.

**Never** manually remove Jaeger's keyspace or any tables in Jaeger's keyspace. And didn't execute any actions
with Cassandra that could lead to removing tables.

Also, if you used a Cassandra cluster with 3 or more nodes and want to scale down it to 1 node, you can't
just remove or disable two nodes in the cluster. It may lead to data loss (and to lost Jaeger's data).
In this case, you have to use Cassandra `nodetool` to remove some nodes from the Cassandra cluster and re-balance
data on nodes.


### Ingress fails with 502 Bad Gateway error

When Jaeger UI is opened via Ingress URL, it is possible that it shows `502 Bad Gateway` error.
The ingress-nginx-controller's logs may show an error as follows:

```bash
upstream sent too big header while reading response header from upstream, client: 10.0.0.15, server: jaeger-query.cloud.test.org
```

To solve this problem, it is necessary to add following annotation to the ingress configuration.

```bash
nginx.ingress.kubernetes.io/proxy-buffer-size: 256k
```

During deploy, following parameters can be used to supply annotations.

```yaml
query:
  ...  
  ingress:
    install: true
    host: jaeger-query.cloud.test.org
  annotations:
    nginx.ingress.kubernetes.io/proxy-buffer-size: 256k
```

