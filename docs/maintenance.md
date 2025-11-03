# Maintenance

This section provides information about Jaeger maintenance issues.

## Change Cassandra User/Password

To change the Cassandra user/password, you can run the upgrade job with new parameters, for example:

```yaml
jaeger:
  serviceName: jaeger
  storage:
    type: "cassandra"
cassandraSchemaJob:
  password: newpassword
  username: newuser
```

Alternatively, you can change the `jaeger-cassandra` secret manually. All the values in the secret
must be encoded with base64.

If you used the existing secret and the `cassandraSchemaJob.existingSecret` parameter when installing the jaeger, then
to change the Cassandra user/password you have to manually edit values in this secret.

Restart all Jaeger pods manually to apply the new Cassandra credentials.

## Scaling Jaeger

It is possible to update collector replicas, resources, and query resources using the upgrade job. All other parameters
during the upgrade should be the same.
For example:

```yaml
jaeger:
  storage:
    type: "cassandra"

cassandraSchemaJob:

query:
  resources:
    requests:
      cpu: 200m
      memory: 200Mi
    limits:
      cpu: 200m
      memory: 200Mi

collector:
  replicas: 2
  resources:
    requests:
      cpu: 200m
      memory: 200Mi
    limits:
      cpu: 200m
      memory: 200Mi
```

## Change Cassandra TTL

Cassandra Time To Live (TTL) is set during keyspace creation (first jaeger installation) and **can't be changed** during
jaeger upgrade procedure.

The default value is 172800 (2 days) for traces and 0 (no TTL) for dependencies. These values
can be changed on first installation using the parameters:

```yaml
cassandraSchemaJob:
  ttl:
    trace: 172800s
    dependencies: 0
```

To change the TTL after the keyspace has already been created, you can connect to Cassandra and change it manually.

Example of query to change TTL for trace data:

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

Example of query to change TTL for dependencies data:

```sql
USE jaegerkeyspace;

ALTER TABLE dependencies_v2 WITH default_time_to_live = 86400;
```

## Cassandra is reinstalled

In case Cassandra has been reinstalled or cleared, then the keyspace has been removed. Keyspace is required for jaeger
operation, so you need to recreate it. To do this, run the upgrade job. For example:

```yaml
cassandraSchemaJob:
  username: user
  password: password
```

The keyspace will be recreated and jaeger will work again.
