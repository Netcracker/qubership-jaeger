{{/* vim: set filetype=mustache: */}}

{{/******************************************************************************************************************/}}
{{/*
Return the public host of the cloud, used to generate hostnames for the components
that are exposed outside the cloud. Returns an empty string when the cloud passport
parameter is not set, in that case nothing is exposed automatically.
The deprecated CLOUD_PUBLIC_HOST name is still supported.
*/}}
{{- define "jaeger.cloudPublicHost" -}}
{{- $global := .Values.global | default dict -}}
{{- $publicHost := coalesce $global.CLOUD_PUBLIC_URL .Values.CLOUD_PUBLIC_URL $global.CLOUD_PUBLIC_HOST .Values.CLOUD_PUBLIC_HOST -}}
{{- if $publicHost -}}
{{- $publicHost -}}
{{- end -}}
{{- end -}}

{{/*
Generate a hostname for a component as "<prefix>-<namespace>.<cloud public host>".
Returns an empty string when the cloud public host is not set.
Usage: include "jaeger.generatedHost" (dict "ctx" $ "prefix" "query")
*/}}
{{- define "jaeger.generatedHost" -}}
{{- $ctx := .ctx -}}
{{- $publicHost := include "jaeger.cloudPublicHost" $ctx -}}
{{- if $publicHost -}}
{{- printf "%s-%s.%s" .prefix ($ctx.Values.NAMESPACE | default $ctx.Release.Namespace) $publicHost -}}
{{- end -}}
{{- end -}}

{{/*
Return "true" when the component has to be exposed outside the cloud.
The "install" flags win when they are specified explicitly, the first specified flag of
the list is used. When none of them is specified, the component is exposed if a hostname
is resolved, either from the parameters of the component or from the cloud public host.
Usage: include "jaeger.exposureEnabled" (dict "flags" (list $route.install $ingress.install) "host" $host)
*/}}
{{- define "jaeger.exposureEnabled" -}}
{{- $decided := "" -}}
{{- range $flag := .flags -}}
{{- if and (eq $decided "") (not (kindIs "invalid" $flag)) -}}
{{- if $flag -}}
{{- $decided = "enabled" -}}
{{- else -}}
{{- $decided = "disabled" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if eq $decided "enabled" -}}
true
{{- else if and (eq $decided "") .host -}}
true
{{- end -}}
{{- end -}}

{{/*
Set default value for hotrod ingress host if not specify in Values.
*/}}
{{- define "hotrod.ingress" -}}
{{- .Values.hotrod.ingress.host | default (include "jaeger.generatedHost" (dict "ctx" . "prefix" "hotrod")) -}}
{{- end -}}

{{/*
Set default value for query ingress host if not specify in Values.
*/}}
{{- define "query.ingress" -}}
{{- .Values.query.ingress.host | default (include "jaeger.generatedHost" (dict "ctx" . "prefix" "query")) -}}
{{- end -}}

{{/*
Set default value for hotrod route host if not specify in Values.
*/}}
{{- define "hotrod.route" -}}
{{- .Values.hotrod.route.host | default (include "jaeger.generatedHost" (dict "ctx" . "prefix" "hotrod")) -}}
{{- end -}}

{{/*
Set default value for query route host if not specify in Values.
*/}}
{{- define "query.route" -}}
{{- .Values.query.route.host | default (include "jaeger.generatedHost" (dict "ctx" . "prefix" "query")) -}}
{{- end -}}

{{/*
Return "true" when GATEWAY_SYSTEM_TYPE asks for Gateway API resources (HTTPRoute/GRPCRoute).
GATEWAY_SYSTEM_TYPE is a cloud passport parameter and may contain several comma-separated
values, for example "legacy-ingress,gateway-api-default", so it is always checked with
"contains" and never with equality.
*/}}
{{- define "jaeger.gatewayApi.enabled" -}}
  {{- if contains "gateway-api-default" (.Values.GATEWAY_SYSTEM_TYPE | default "") -}}
      true
  {{- end -}}
{{- end -}}

{{/*
Return "true" when GATEWAY_SYSTEM_TYPE asks for legacy Ingress resources.
An unset or empty value is treated as "legacy-ingress" to keep the behavior
of the existing installations unchanged.
*/}}
{{- define "jaeger.legacyIngress.enabled" -}}
  {{- if contains "legacy-ingress" (.Values.GATEWAY_SYSTEM_TYPE | default "legacy-ingress") -}}
      true
  {{- end -}}
{{- end -}}

{{/*
Render the parentRefs section of a route.
Uses the explicitly specified parentRefs when they are set, otherwise resolves the shared
external Gateway from the cloud passport parameters. The Gateway is never hardcoded.
Usage: {{- include "jaeger.gatewayApi.parentRefs" (dict "ctx" $ "parentRefs" $spec.parentRefs) | nindent 4 }}
*/}}
{{- define "jaeger.gatewayApi.parentRefs" -}}
{{- $ctx := .ctx -}}
{{- if .parentRefs -}}
{{- $refs := list -}}
{{- range $ref := .parentRefs -}}
{{- $new := deepCopy $ref -}}
{{- $_ := set $new "group" ($ref.group | default "gateway.networking.k8s.io") -}}
{{- $_ := set $new "kind" ($ref.kind | default "Gateway") -}}
{{- $refs = append $refs $new -}}
{{- end -}}
{{- toYaml $refs -}}
{{- else if $ctx.Values.PEER_NAMESPACE -}}
- group: gateway.networking.k8s.io
  kind: Gateway
  name: edge-router
  namespace: {{ $ctx.Values.CONTROLLER_NAMESPACE | default $ctx.Release.Namespace }}
{{- else -}}
- group: gateway.networking.k8s.io
  kind: Gateway
  name: {{ $ctx.Values.GATEWAY_SYSTEM_NAME | default "default-external-gateway" }}
  namespace: {{ $ctx.Values.GATEWAY_SYSTEM_NAMESPACE | default "gateway-system" }}
{{- end -}}
{{- end -}}

{{/*
Render one backendRef of a route.
The "group", "kind" and "weight" fields are defaulted by the API server, so they are always
rendered explicitly, otherwise the resource is permanently out of sync in ArgoCD.
Usage: {{- include "jaeger.gatewayApi.backendRef" (dict "name" $name "port" $port "weight" $weight) | nindent 4 }}
*/}}
{{- define "jaeger.gatewayApi.backendRef" -}}
- group: {{ .group | default "" | quote }}
  kind: {{ .kind | default "Service" }}
  name: {{ .name }}
  port: {{ .port }}
  weight: {{ if kindIs "invalid" .weight }}1{{ else }}{{ .weight }}{{ end }}
{{- end -}}

{{/*
Render a list of route rules specified as is in the values, with the backendRefs normalized
to contain the fields defaulted by the API server.
Usage: {{- include "jaeger.gatewayApi.rules" (dict "rules" $rules) | nindent 4 }}
*/}}
{{- define "jaeger.gatewayApi.rules" -}}
{{- $rules := list -}}
{{- range $rule := .rules -}}
{{- $newRule := deepCopy $rule -}}
{{- if $rule.matches -}}
{{- $matches := list -}}
{{- range $match := $rule.matches -}}
{{- $newMatch := deepCopy $match -}}
{{- if $match.method -}}
{{- $method := deepCopy $match.method -}}
{{- $_ := set $method "type" ($match.method.type | default "Exact") -}}
{{- $_ := set $newMatch "method" $method -}}
{{- end -}}
{{- if $match.headers -}}
{{- $headers := list -}}
{{- range $header := $match.headers -}}
{{- $newHeader := deepCopy $header -}}
{{- $_ := set $newHeader "type" ($header.type | default "Exact") -}}
{{- $headers = append $headers $newHeader -}}
{{- end -}}
{{- $_ := set $newMatch "headers" $headers -}}
{{- end -}}
{{- $matches = append $matches $newMatch -}}
{{- end -}}
{{- $_ := set $newRule "matches" $matches -}}
{{- end -}}
{{- if $rule.backendRefs -}}
{{- $refs := list -}}
{{- range $ref := $rule.backendRefs -}}
{{- $new := deepCopy $ref -}}
{{- $_ := set $new "group" ($ref.group | default "") -}}
{{- $_ := set $new "kind" ($ref.kind | default "Service") -}}
{{- if kindIs "invalid" $ref.weight -}}
{{- $_ := set $new "weight" 1 -}}
{{- end -}}
{{- $refs = append $refs $new -}}
{{- end -}}
{{- $_ := set $newRule "backendRefs" $refs -}}
{{- end -}}
{{- $rules = append $rules $newRule -}}
{{- end -}}
{{- toYaml $rules -}}
{{- end -}}

{{/*
Render the hostnames section of a route.
Falls back to the hosts of the matching Ingress so that a route needs no extra
parameters when the Ingress hosts are already configured.
Usage: {{- include "jaeger.gatewayApi.hostnames" (dict "ctx" $ "hosts" $hosts) | nindent 4 }}
*/}}
{{- define "jaeger.gatewayApi.hostnames" -}}
{{- $ctx := .ctx -}}
{{- $hostnames := list -}}
{{- range $hostname := .hosts -}}
{{- $hostnames = append $hostnames (tpl (toString $hostname) $ctx | trim | trimAll "\"") -}}
{{- end -}}
{{- toYaml $hostnames -}}
{{- end -}}

{{/*
Return the list of hostnames for the collector routes.
The hostnames of the route win, then the hosts of the matching Ingress are used, both in
the single ".host" and in the list ".hosts" syntax. When nothing is specified, a hostname
is generated from the cloud public host, if it is set.
Usage: include "collector.gatewayApi.hosts" (dict "ctx" $ "route" $routeSpec "ingress" .Values.collector.ingress.http "prefix" "collector")
*/}}
{{- define "collector.gatewayApi.hosts" -}}
{{- $routeSpec := .route | default dict -}}
{{- if $routeSpec.hosts -}}
{{- toYaml $routeSpec.hosts -}}
{{- else -}}
{{- $hosts := list -}}
{{- range $entry := include "collector.ingress.entries" (dict "ctx" .ctx "ingress" .ingress "prefix" .prefix) | fromYamlArray -}}
{{- $hosts = append $hosts $entry.host -}}
{{- end -}}
{{- toYaml $hosts -}}
{{- end -}}
{{- end -}}

{{/*
Base resource labels: name, app.kubernetes.io/name, component, part-of, managed-by.
Instance, version, technology are set inline in chart templates, not here.
Usage: {{- include "jaeger.labels" (dict "ctx" . "name" $name "component" $component) | nindent 4 }}
       Add instance, version, technology inline in the template as needed.
*/}}
{{- define "jaeger.labels" -}}
{{- $ctx := index . "ctx" | default . -}}
{{- $name := index . "name" -}}
{{- $component := index . "component" -}}
name: {{ $name }}
app.kubernetes.io/name: {{ $name }}
app.kubernetes.io/component: {{ $component }}
app: jaeger
app.kubernetes.io/part-of: jaeger
app.kubernetes.io/managed-by: {{ $ctx.Release.Service }}
{{- end -}}

{{/*
Return list of hosts for Ingress.
Support as already existing syntax with only one .host and syntax to specify list of hosts inside one Ingress
*/}}
{{- define "collector.ingress.grpc.rules" -}}
{{- range $entry := include "collector.ingress.entries" (dict "ctx" $ "ingress" $.Values.collector.ingress.grpc "prefix" "collector-grpc") | fromYamlArray }}
- host: {{ tpl $entry.host $ | quote }}
  http:
    paths: {{ include "collector.ingress.grpc.hostPaths" (list $ $entry) | trim | nindent 6 }}
{{- end -}}
{{- end -}}

{{- define "collector.ingress.http.rules" -}}
{{- range $entry := include "collector.ingress.entries" (dict "ctx" $ "ingress" $.Values.collector.ingress.http "prefix" "collector") | fromYamlArray }}
- host: {{ tpl $entry.host $ | quote }}
  http:
    paths: {{ include "collector.ingress.http.hostPaths" (list $ $entry) | trim | nindent 6 }}
{{- end -}}
{{- end -}}

{{/*
Return the list of host entries of a collector Ingress.
Supports both the single ".host" and the list ".hosts" syntax. When no host is specified,
a hostname is generated from the cloud public host, if it is set.
Usage: include "collector.ingress.entries" (dict "ctx" $ "ingress" $ingress "prefix" "collector")
*/}}
{{- define "collector.ingress.entries" -}}
{{- $ingress := .ingress | default dict -}}
{{- $entries := list -}}
{{- if $ingress.host -}}
{{- $entries = append $entries (dict "host" $ingress.host) -}}
{{- end -}}
{{- range $ingress.hosts -}}
{{- if .host -}}
{{- $entries = append $entries . -}}
{{- end -}}
{{- end -}}
{{- if not $entries -}}
{{- $generated := include "jaeger.generatedHost" (dict "ctx" .ctx "prefix" .prefix) -}}
{{- if $generated -}}
{{- $entries = append $entries (dict "host" $generated) -}}
{{- end -}}
{{- end -}}
{{- toYaml $entries -}}
{{- end -}}

{{/*
Return a stable resource name for collector HTTPRoute resources.
*/}}
{{- define "collector.httpRoute.resourceName" -}}
{{- $ := index . 0 -}}
{{- $routeType := index . 1 -}}
{{ printf "%s-%s-collector" $.Values.jaeger.serviceName $routeType | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/*
Render shared HTTPRoute rules.
*/}}
{{- define "collector.httpRoute.rules" -}}
{{- $ := index . 0 -}}
{{- $pathsToApply := index . 1 -}}
{{- $defaultServiceName := printf "%s-collector" $.Values.jaeger.serviceName -}}
{{- range $pathsToApply }}
- matches:
    - path:
        type: PathPrefix
        value: {{ .prefix | quote }}
  {{- if .rewritePrefix }}
  filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: {{ .rewritePrefix | quote }}
  {{- end }}
  backendRefs:
    {{- include "jaeger.gatewayApi.backendRef" (dict "name" (coalesce .service.name $defaultServiceName) "port" .service.port "weight" .service.weight) | nindent 4 }}
{{- end -}}
{{- end -}}

{{/*
Return list of paths and endpoints for one host
*/}}
{{- define "collector.ingress.grpc.hostPaths" -}}
{{/* Restore the global context in the "$" */}}
{{/* Start render template in the relative content, here .Values.jaeger.collector.ingress.grpc.hosts */}}
{{- $ := index . 0 }}
{{- $defaultServiceName := printf "%s-collector" $.Values.jaeger.serviceName -}}
{{- with index . 1 }}
{{- $pathsToApply := coalesce .paths $.Values.collector.ingress.grpc.defaultPaths -}}
{{- range $pathsToApply }}
- path: {{ .prefix }}
  pathType: Prefix
  backend:
    service:
      name: {{ coalesce .service.name $defaultServiceName }}
      port:
        number: {{ .service.port }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Return list of paths and endpoints for one host
*/}}
{{- define "collector.ingress.http.hostPaths" -}}
{{/* Restore the global context in the "$" */}}
{{- $ := index . 0 }}
{{- $defaultServiceName := printf "%s-collector" $.Values.jaeger.serviceName -}}
{{/* Start render template in the relative content, here .Values.jaeger.collector.ingress.http.hosts */}}
{{- with index . 1 }}
{{- $pathsToApply := coalesce .paths $.Values.collector.ingress.http.defaultPaths -}}
{{- range $pathsToApply }}
- path: {{ .prefix }}
  pathType: Prefix
  backend:
    service:
      name: {{ coalesce .service.name $defaultServiceName }}
      port:
        number: {{ .service.port }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/******************************************************************************************************************/}}

{{/*
Find a collector image in various places.
Image can be found from:
* from default values .Values.collector.image
*/}}
{{- define "collector.image" -}}
  {{- if .Values.collector.image -}}
    {{- printf "%s" .Values.collector.image -}}
  {{- else -}}
    {{- print "jaegertracing/jaeger:2.13.0" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a jaeger-query image in various places.
Image can be found from:
* from default values .Values.query.image
*/}}
{{- define "query.image" -}}
  {{- if .Values.query.image -}}
    {{- printf "%s" .Values.query.image -}}
  {{- else -}}
    {{- print "jaegertracing/jaeger:2.13.0" -}}
  {{- end -}}
{{- end -}}

{{/*
Return collector runtime config secret name.
*/}}
{{- define "collector.runtimeConfig.secretName" -}}
  {{- printf "%s-collector-configuration" .Values.jaeger.serviceName -}}
{{- end -}}

{{/*
Return collector runtime config key.
*/}}
{{- define "collector.runtimeConfig.key" -}}
  {{- print "config.yaml" -}}
{{- end -}}

{{/*
Return query runtime config secret name.
*/}}
{{- define "query.runtimeConfig.secretName" -}}
  {{- printf "%s-query-configuration" .Values.jaeger.serviceName -}}
{{- end -}}

{{/*
Return query runtime config key.
*/}}
{{- define "query.runtimeConfig.key" -}}
  {{- print "config.yaml" -}}
{{- end -}}

{{/*
Find a envoy image in various places.
Image can be found from:
* from default values .Values.proxy.image
*/}}
{{- define "proxy.image" -}}
  {{- if .Values.proxy.image -}}
    {{- printf "%s" .Values.proxy.image -}}
  {{- else -}}
    {{- print "envoyproxy/envoy:v1.35.2" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a hotrod example image in various places.
Image can be found from:
* from default values .Values.hotrod.image
*/}}
{{- define "hotrod.image" -}}
  {{- if .Values.hotrod.image -}}
    {{- printf "%s" .Values.hotrod.image -}}
  {{- else -}}
    {{- print "jaegertracing/example-hotrod:1.76.0" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a indexCleaner image in various places.
Image can be found from:
* from default values .Values.elasticsearch.indexCleaner.image
*/}}
{{- define "indexCleaner.image" -}}
  {{- if .Values.elasticsearch.indexCleaner.image -}}
    {{- printf "%s" .Values.elasticsearch.indexCleaner.image -}}
  {{- else -}}
    {{- print "jaegertracing/jaeger-es-index-cleaner:1.76.0" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a rollover image in various places.
Image can be found from:
* from default values .Values.elasticsearch.rollover.image
*/}}
{{- define "rollover.image" -}}
  {{- if .Values.elasticsearch.rollover.image -}}
    {{- printf "%s" .Values.elasticsearch.rollover.image -}}
  {{- else -}}
    {{- print "jaegertracing/jaeger-es-rollover:1.76.0" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a jaeger-integration-tests image in various places.
Image can be found from:
* from default values .Values.collector.image
*/}}
{{- define "jaeger-integration-tests.image" -}}
  {{- if .Values.integrationTests.image -}}
    {{- printf "%s" .Values.integrationTests.image -}}
  {{- else -}}
    {{- print "ghcr.io/netcracker/jaeger-integration-tests:main" -}}
  {{- end -}}
{{- end -}}

{{/*
Determine if memory limiter should be enabled.
Enables memory limiter if:
1. Explicitly enabled in collector.config.processors.memory_limiter.enabled, OR
2. Integration tests are installed AND tags contain "memory_limiter"
*/}}
{{- define "collector.memoryLimiterEnabled" -}}
  {{- $explicitlyEnabled := .Values.collector.config.processors.memory_limiter.enabled -}}
  {{- $integrationTestsWithMemoryLimiter := false -}}
  {{- if and .Values.integrationTests.install .Values.integrationTests.tags -}}
    {{- $integrationTestsWithMemoryLimiter = (regexMatch ".*memory_limiter.*" .Values.integrationTests.tags) -}}
  {{- end -}}
  {{- if or $explicitlyEnabled $integrationTestsWithMemoryLimiter -}}
true
  {{- else -}}
false
  {{- end -}}
{{- end -}}

{{/*
Find a Deployment Status Provisioner image in various places.
*/}}
{{- define "deployment-status-provisioner.image" -}}
  {{- if .Values.statusProvisioner.image -}}
    {{- printf "%s" .Values.statusProvisioner.image -}}
  {{- else -}}
    {{- print "ghcr.io/netcracker/qubership-deployment-status-provisioner:0.2.4" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a readiness-probe image in various places.
*/}}
{{- define "readiness-probe.image" -}}
  {{- if .Values.readinessProbe.image -}}
    {{- printf "%s" .Values.readinessProbe.image -}}
  {{- else -}}
    {{- print "ghcr.io/netcracker/jaeger-readiness-probe:main" -}}
  {{- end -}}
{{- end -}}

{{/*
Find a Spark Dependencies image in various places.
*/}}
{{- define "spark-dependencies.image" -}}
  {{- if .Values.spark.image -}}
    {{- printf "%s" .Values.spark.image -}}
  {{- else -}}
    {{- print "ghcr.io/jaegertracing/spark-dependencies/spark-dependencies:latest" -}}
  {{- end -}}
{{- end -}}

{{/******************************************************************************************************************/}}

{{/*
Return name of secret for cassandraSchemaJob.
*/}}
{{- define "cassandraSchemaJob.secretName" -}}
  {{- if .Values.cassandraSchemaJob.existingSecret -}}
    {{- printf "%s" (.Values.cassandraSchemaJob.existingSecret)  -}}
  {{- else -}}
    {{- print "jaeger-cassandra" -}}
  {{- end -}}
{{- end -}}

{{/*
Return name of secret for cassandraSchemaJob TLS.
*/}}
{{- define "cassandraSchemaJob.tls.secretName" -}}
  {{- if .Values.cassandraSchemaJob.tls.existingSecret -}}
    {{- printf "%s" (.Values.cassandraSchemaJob.tls.existingSecret)  -}}
  {{- else -}}
    {{- print "jaeger-cassandra-tls" -}}
  {{- end -}}
{{- end -}}

{{/*
Return host for cassandra database.
*/}}
{{- define "cassandraSchemaJob.host" -}}
  {{- if .Values.cassandraSchemaJob.host -}}
    {{- printf "%s" (.Values.cassandraSchemaJob.host) -}}
  {{- else -}}
    {{- if .Values.INFRA_CASSANDRA_HOST -}}
      {{- printf "%s" (.Values.INFRA_CASSANDRA_HOST) -}}
    {{- else -}}
      {{- print "cassandra.cassandra.svc" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return port for cassandra database.
*/}}
{{- define "cassandraSchemaJob.port" -}}
  {{- if .Values.cassandraSchemaJob.port -}}
    {{- printf "%v" (.Values.cassandraSchemaJob.port) -}}
  {{- else -}}
    {{- if .Values.INFRA_CASSANDRA_PORT -}}
      {{- printf "%v" (.Values.INFRA_CASSANDRA_PORT) -}}
    {{- else -}}
      {{- print "9042" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return datacenter for cassandra database.
*/}}
{{- define "cassandraSchemaJob.datacenter" -}}
  {{- if .Values.cassandraSchemaJob.datacenter -}}
    {{- printf "%s" (.Values.cassandraSchemaJob.datacenter) -}}
  {{- else -}}
    {{- if .Values.INFRA_CASSANDRA_DC -}}
      {{- printf "%s" (.Values.INFRA_CASSANDRA_DC) -}}
    {{- else -}}
      {{- print "" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return username for cassandra database.
*/}}
{{- define "cassandraSchemaJob.userName" -}}
  {{- if .Values.cassandraSchemaJob.username -}}
    {{- printf "%s" (.Values.cassandraSchemaJob.username) -}}
  {{- else if .Values.cassandraSchemaJob.existingSecret -}}
    {{- $secret := lookup "v1" "Secret" (.Values.NAMESPACE | default .Release.Namespace) .Values.cassandraSchemaJob.existingSecret -}}
    {{- if not $secret -}}
      {{- fail (printf "cassandra existingSecret %q was not found in namespace %q" .Values.cassandraSchemaJob.existingSecret (.Values.NAMESPACE | default .Release.Namespace)) -}}
    {{- end -}}
    {{- $username := index $secret.data "username" -}}
    {{- if not $username -}}
      {{- fail (printf "cassandra existingSecret %q does not contain key %q" .Values.cassandraSchemaJob.existingSecret "username") -}}
    {{- end -}}
    {{- $username | b64dec -}}
  {{- else -}}
    {{- if .Values.INFRA_CASSANDRA_USERNAME -}}
      {{- printf "%s" (.Values.INFRA_CASSANDRA_USERNAME) -}}
    {{- else -}}
      {{- print "" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return list of allowed authenticators for Cassandra as string joined using comma (,).
Will use the default list of values if user don't specify custom values.
For example: org.apache.cassandra.auth.PasswordAuthenticator,com.instaclustr.cassandra.auth.SharedSecretAuthenticator,...
*/}}
{{- define "cassandraSchemaJob.allowedAuthenticators" -}}
  {{- if .Values.cassandraSchemaJob.allowedAuthenticators -}}
    {{- join "," .Values.cassandraSchemaJob.allowedAuthenticators -}}
  {{- else -}}
    {{- join "," .Values.cassandraSchemaJob.defaultAllowedAuthenticators -}}
  {{- end -}}
{{- end -}}

{{/*
Return password for cassandra database.
*/}}
{{- define "cassandraSchemaJob.password" -}}
  {{- if .Values.cassandraSchemaJob.password -}}
    {{- printf "%s" (.Values.cassandraSchemaJob.password) -}}
  {{- else if .Values.cassandraSchemaJob.existingSecret -}}
    {{- $secret := lookup "v1" "Secret" (.Values.NAMESPACE | default .Release.Namespace) .Values.cassandraSchemaJob.existingSecret -}}
    {{- if not $secret -}}
      {{- fail (printf "cassandra existingSecret %q was not found in namespace %q" .Values.cassandraSchemaJob.existingSecret (.Values.NAMESPACE | default .Release.Namespace)) -}}
    {{- end -}}
    {{- $password := index $secret.data "password" -}}
    {{- if not $password -}}
      {{- fail (printf "cassandra existingSecret %q does not contain key %q" .Values.cassandraSchemaJob.existingSecret "password") -}}
    {{- end -}}
    {{- $password | b64dec -}}
  {{- else -}}
    {{- if .Values.INFRA_CASSANDRA_PASSWORD -}}
      {{- printf "%s" (.Values.INFRA_CASSANDRA_PASSWORD) -}}
    {{- else -}}
      {{- print "" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return name of secret for OpenSearch/Elasticsearch TLS.
*/}}
{{- define "elasticsearch.tls.secretName" -}}
  {{- if .Values.elasticsearch.client.tls.existingSecret -}}
    {{- printf "%s" (.Values.elasticsearch.client.tls.existingSecret)  -}}
  {{- else -}}
    {{- if .prehook -}}
      {{- printf "%s-es-pre-hook-tls-assets" (.Values.jaeger.serviceName) -}}
    {{- else -}}
      {{- printf "%s-elasticsearch-tls-assets" (.Values.jaeger.serviceName) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return URL for OpenSearch/Elasticsearch.
*/}}
{{- define "elasticsearch.url" -}}
  {{- if .Values.elasticsearch.client.url -}}
    {{- printf "%s://%s" (.Values.elasticsearch.client.scheme) (.Values.elasticsearch.client.url) -}}
  {{- else -}}
    {{- if .Values.INFRA_OPENSEARCH_URL -}}
      {{- printf "%s" .Values.INFRA_OPENSEARCH_URL -}}
    {{- else -}}
      {{- print "" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return username for OpenSearch/Elasticsearch.
*/}}
{{- define "elasticsearch.userName" -}}
  {{- if .Values.elasticsearch.client.username -}}
    {{- printf "%s" (.Values.elasticsearch.client.username) -}}
  {{- else if .Values.elasticsearch.existingSecret -}}
    {{- $secret := lookup "v1" "Secret" (.Values.NAMESPACE | default .Release.Namespace) .Values.elasticsearch.existingSecret -}}
    {{- if not $secret -}}
      {{- fail (printf "elasticsearch existingSecret %q was not found in namespace %q" .Values.elasticsearch.existingSecret (.Values.NAMESPACE | default .Release.Namespace)) -}}
    {{- end -}}
    {{- $username := index $secret.data "username" -}}
    {{- if not $username -}}
      {{- fail (printf "elasticsearch existingSecret %q does not contain key %q" .Values.elasticsearch.existingSecret "username") -}}
    {{- end -}}
    {{- $username | b64dec -}}
  {{- else -}}
    {{- if .Values.INFRA_OPENSEARCH_USERNAME -}}
      {{- printf "%s" .Values.INFRA_OPENSEARCH_USERNAME -}}
    {{- else -}}
      {{- print "" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Return password for OpenSearch/Elasticsearch.
*/}}
{{- define "elasticsearch.password" -}}
  {{- if .Values.elasticsearch.client.password -}}
    {{- printf "%s" (.Values.elasticsearch.client.password) -}}
  {{- else if .Values.elasticsearch.existingSecret -}}
    {{- $secret := lookup "v1" "Secret" (.Values.NAMESPACE | default .Release.Namespace) .Values.elasticsearch.existingSecret -}}
    {{- if not $secret -}}
      {{- fail (printf "elasticsearch existingSecret %q was not found in namespace %q" .Values.elasticsearch.existingSecret (.Values.NAMESPACE | default .Release.Namespace)) -}}
    {{- end -}}
    {{- $password := index $secret.data "password" -}}
    {{- if not $password -}}
      {{- fail (printf "elasticsearch existingSecret %q does not contain key %q" .Values.elasticsearch.existingSecret "password") -}}
    {{- end -}}
    {{- $password | b64dec -}}
  {{- else -}}
    {{- if .Values.INFRA_OPENSEARCH_PASSWORD -}}
      {{- printf "%s" .Values.INFRA_OPENSEARCH_PASSWORD -}}
    {{- else -}}
      {{- print "" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Render index options for Jaeger v2 Elasticsearch/OpenSearch storage.
*/}}
{{- define "elasticsearch.runtime.indexOptions" -}}
{{- $index := . -}}
{{- if hasKey $index "dateLayout" }}
date_layout: {{ get $index "dateLayout" | quote }}
{{- end }}
{{- if hasKey $index "rolloverFrequency" }}
rollover_frequency: {{ get $index "rolloverFrequency" | quote }}
{{- end }}
{{- if hasKey $index "shards" }}
shards: {{ get $index "shards" }}
{{- end }}
{{- if hasKey $index "replicas" }}
replicas: {{ get $index "replicas" }}
{{- end }}
{{- if hasKey $index "priority" }}
priority: {{ get $index "priority" }}
{{- end }}
{{- end -}}

{{/*
Render indices section for Jaeger v2 Elasticsearch/OpenSearch storage.
*/}}
{{- define "elasticsearch.runtime.indices" -}}
{{- if .Values.elasticsearch.indexPrefix }}
index_prefix: {{ .Values.elasticsearch.indexPrefix | quote }}
{{- end }}
{{- with .Values.elasticsearch.indices }}
{{- with .spans }}
{{- $spans := include "elasticsearch.runtime.indexOptions" . | trim }}
{{- if $spans }}
spans:
{{ $spans | nindent 2 }}
{{- end }}
{{- end }}
{{- with .services }}
{{- $services := include "elasticsearch.runtime.indexOptions" . | trim }}
{{- if $services }}
services:
{{ $services | nindent 2 }}
{{- end }}
{{- end }}
{{- with .dependencies }}
{{- $dependencies := include "elasticsearch.runtime.indexOptions" . | trim }}
{{- if $dependencies }}
dependencies:
{{ $dependencies | nindent 2 }}
{{- end }}
{{- end }}
{{- with .sampling }}
{{- $sampling := include "elasticsearch.runtime.indexOptions" . | trim }}
{{- if $sampling }}
sampling:
{{ $sampling | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Render Jaeger v2 Elasticsearch/OpenSearch runtime storage config.
*/}}
{{- define "elasticsearch.runtime.config" -}}
elasticsearch:
  server_urls:
    {{- $url := include "elasticsearch.url" . }}
    {{- if $url }}
    - {{ $url | quote }}
    {{- end }}
  auth:
    basic:
      username: {{ include "elasticsearch.userName" . | quote }}
      password: {{ include "elasticsearch.password" . | quote }}
  {{- if hasKey .Values.elasticsearch "remoteReadClusters" }}
  remote_read_clusters:
    {{- toYaml .Values.elasticsearch.remoteReadClusters | nindent 4 }}
  {{- end }}
  {{- if hasKey .Values.elasticsearch "disableHealthCheck" }}
  disable_health_check: {{ .Values.elasticsearch.disableHealthCheck }}
  {{- end }}
  {{- if hasKey .Values.elasticsearch "sendGetBodyAs" }}
  send_get_body_as: {{ .Values.elasticsearch.sendGetBodyAs | quote }}
  {{- end }}
  {{- if hasKey .Values.elasticsearch "queryTimeout" }}
  query_timeout: {{ .Values.elasticsearch.queryTimeout | quote }}
  {{- end }}
  {{- if hasKey .Values.elasticsearch "httpCompression" }}
  http_compression: {{ .Values.elasticsearch.httpCompression }}
  {{- end }}
  {{- if .Values.elasticsearch.customHeaders }}
  custom_headers:
    {{- toYaml .Values.elasticsearch.customHeaders | nindent 4 }}
  {{- end }}
  {{- if .Values.elasticsearch.bulkProcessing }}
  bulk_processing:
    {{- with .Values.elasticsearch.bulkProcessing.maxBytes }}
    max_bytes: {{ . }}
    {{- end }}
    {{- with .Values.elasticsearch.bulkProcessing.maxActions }}
    max_actions: {{ . }}
    {{- end }}
    {{- with .Values.elasticsearch.bulkProcessing.flushInterval }}
    flush_interval: {{ . | quote }}
    {{- end }}
    {{- with .Values.elasticsearch.bulkProcessing.workers }}
    workers: {{ . }}
    {{- end }}
  {{- end }}
  {{- if hasKey .Values.elasticsearch "version" }}
  version: {{ .Values.elasticsearch.version }}
  {{- end }}
  {{- if hasKey .Values.elasticsearch "logLevel" }}
  log_level: {{ .Values.elasticsearch.logLevel | quote }}
  {{- end }}
  {{- $indices := include "elasticsearch.runtime.indices" . | trim }}
  {{- if $indices }}
  indices:
{{ $indices | nindent 4 }}
  {{- end }}
  {{- if hasKey .Values.elasticsearch "useAliases" }}
  use_aliases: {{ .Values.elasticsearch.useAliases }}
  {{- end }}
  {{- if hasKey .Values.elasticsearch "createMappings" }}
  create_mappings: {{ .Values.elasticsearch.createMappings }}
  {{- end }}
  {{- if hasKey .Values.elasticsearch "useIlm" }}
  use_ilm: {{ .Values.elasticsearch.useIlm }}
  {{- end }}
  {{- if hasKey .Values.elasticsearch "maxDocCount" }}
  max_doc_count: {{ .Values.elasticsearch.maxDocCount }}
  {{- end }}
  {{- if hasKey .Values.elasticsearch "maxSpanAge" }}
  max_span_age: {{ .Values.elasticsearch.maxSpanAge | quote }}
  {{- end }}
  {{- if hasKey .Values.elasticsearch "serviceCacheTtl" }}
  service_cache_ttl: {{ .Values.elasticsearch.serviceCacheTtl | quote }}
  {{- end }}
  {{- if hasKey .Values.elasticsearch "adaptiveSamplingLookback" }}
  adaptive_sampling_lookback: {{ .Values.elasticsearch.adaptiveSamplingLookback | quote }}
  {{- end }}
  {{- if .Values.elasticsearch.tagsAsFields }}
  tags_as_fields:
    {{- if hasKey .Values.elasticsearch.tagsAsFields "all" }}
    all: {{ .Values.elasticsearch.tagsAsFields.all }}
    {{- end }}
    {{- if hasKey .Values.elasticsearch.tagsAsFields "dotReplacement" }}
    dot_replacement: {{ .Values.elasticsearch.tagsAsFields.dotReplacement | quote }}
    {{- end }}
    {{- if hasKey .Values.elasticsearch.tagsAsFields "configFile" }}
    config_file: {{ .Values.elasticsearch.tagsAsFields.configFile | quote }}
    {{- end }}
    {{- if hasKey .Values.elasticsearch.tagsAsFields "include" }}
    include: {{ .Values.elasticsearch.tagsAsFields.include | quote }}
    {{- end }}
  {{- end }}
  tls:
    {{- if .Values.elasticsearch.client.tls.enabled }}
    {{- if .Values.elasticsearch.client.tls.insecureSkipVerify }}
    insecure_skip_verify: true
    {{- else }}
    ca_file: /es-tls/ca-cert.pem
    cert_file: /es-tls/client-cert.pem
    key_file: /es-tls/client-key.pem
    {{- end }}
    {{- else }}
    insecure: true
    {{- end }}
  {{- if .Values.elasticsearch.sniffing }}
  sniffing:
    {{- if hasKey .Values.elasticsearch.sniffing "enabled" }}
    enabled: {{ .Values.elasticsearch.sniffing.enabled }}
    {{- end }}
    {{- if hasKey .Values.elasticsearch.sniffing "useHttps" }}
    use_https: {{ .Values.elasticsearch.sniffing.useHttps }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Return mandatory security settings merged with a container's custom context.
*/}}
{{- define "jaeger.hardenedContainerSecurityContext" -}}
  {{- $context := deepCopy (default dict .) -}}
  {{- $_ := set $context "allowPrivilegeEscalation" false -}}
  {{- $_ := set $context "readOnlyRootFilesystem" true -}}
  {{- $capabilities := deepCopy (default dict (get $context "capabilities")) -}}
  {{- $_ := set $capabilities "drop" (list "ALL") -}}
  {{- $_ := set $context "capabilities" $capabilities -}}
  {{- toYaml $context -}}
{{- end -}}

{{/*
Return mandatory pod security settings merged with a pod's custom context.
*/}}
{{- define "jaeger.hardenedPodSecurityContext" -}}
  {{- $context := deepCopy (default dict (index . 0)) -}}
  {{- $root := index . 1 -}}
  {{- $_ := set $context "runAsNonRoot" true -}}
  {{- $_ := set $context "seccompProfile" (dict "type" "RuntimeDefault") -}}
  {{- if eq (default "" $root.Values.PAAS_PLATFORM) "KUBERNETES" -}}
    {{- if not (hasKey $context "runAsUser") -}}
      {{- $_ := set $context "runAsUser" 1000 -}}
    {{- end -}}
    {{- if not (hasKey $context "runAsGroup") -}}
      {{- $_ := set $context "runAsGroup" 1000 -}}
    {{- end -}}
  {{- end -}}
  {{- toYaml $context -}}
{{- end -}}

{{/*
Calculates resources that should be monitored during deployment by Deployment Status Provisioner.
*/}}
{{- define "jaeger.monitoredResources" -}}
    {{- if .Values.collector.install }}
        {{- printf "Deployment %s-collector, " .Values.jaeger.serviceName -}}
    {{- end }}
    {{- if .Values.query.install }}
        {{- printf "Deployment %s-query, " .Values.jaeger.serviceName -}}
    {{- end }}
    {{- if .Values.hotrod.install }}
        {{- printf "Deployment %s-hotrod, " .Values.jaeger.serviceName -}}
    {{- end }}
    {{- if .Values.integrationTests.install }}
        {{- printf "Deployment %s, " .Values.integrationTests.service.name -}}
    {{- end }}
{{- end -}}

{{/******************************************************************************************************************/}}

{{/*
Prepare args for readiness-probe container.
*/}}
{{- define "readinessProbe.args" -}}
  {{- if .Values.readinessProbe.args }}
    {{- range .Values.readinessProbe.args }}
            - {{ . | quote }}
      {{- end }}
  {{- else }}
            - "-namespace={{ .Values.NAMESPACE | default .Release.Namespace }}"
    {{- if eq .Values.jaeger.storage.type "cassandra" }}
            - "-storage=cassandra"
            - "-authSecretName=jaeger-cassandra"
            - "-datacenter={{ include "cassandraSchemaJob.datacenter" . }}"
      {{- if .Values.cassandraSchemaJob.keyspace }}
            - "-keyspace={{ .Values.cassandraSchemaJob.keyspace }}"
      {{- end }}
            - "-host={{ include "cassandraSchemaJob.host" . }}"
            - "-port={{ include "cassandraSchemaJob.port" . }}"
      {{- if .Values.cassandraSchemaJob.tls.enabled }}
            - "-tlsEnabled=true"
        {{- if .Values.cassandraSchemaJob.tls.insecureSkipVerify }}
            - "-insecureSkipVerify=true"
        {{- else }}
            - "-caPath=/cassandra-tls/ca-cert.pem"
            - "-crtPath=/cassandra-tls/client-cert.pem"
            - "-keyPath=/cassandra-tls/client-key.pem"
        {{- end }}
      {{- end }}
    {{- else }}
            - "-storage=opensearch"
            - "-host={{ include "elasticsearch.url" . }}"
            - "-authSecretName=jaeger-elasticsearch"
      {{- if .Values.elasticsearch.client.tls.enabled }}
            - "-tlsEnabled=true"
        {{- if .Values.elasticsearch.client.tls.insecureSkipVerify }}
            - "-insecureSkipVerify=true"
        {{- else }}
            - "-caPath=/es-tls/ca-cert.pem"
            - "-crtPath=/es-tls/client-cert.pem"
            - "-keyPath=/es-tls/client-key.pem"
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Generate list of args for collector
*/}}
{{- define "collector.args" -}}
    {{- if .Values.collector.args }}
        {{- range .Values.collector.args }}
            - {{ . | quote }}
        {{- end }}
    {{- else }}
            - "--config=/conf/config.yaml"
    {{- end }}
{{- end -}}

{{/*
Generate list of env variables for collector.
Returns an empty string when there is nothing to render, so the caller can omit
the "env:" key entirely instead of emitting an empty section.
*/}}
{{- define "collector.env" -}}
{{- if eq .Values.jaeger.storage.type "elasticsearch" }}
  {{- range $key, $value := .Values.elasticsearch.env }}
- name: {{ $key | quote }}
  value: {{ $value | quote }}
  {{- end }}
  {{- with .Values.elasticsearch.extraEnv }}
    {{- toYaml . | nindent 0 }}
  {{- end }}
{{- end }}
{{- with .Values.collector.extraEnv }}
  {{- toYaml . | nindent 0 }}
{{- end }}
{{- end -}}

{{/*
Generate certificate volumes for TLS configuration
*/}}
{{- define "jaeger.certificateVolumes" -}}
{{- if .Values.cassandraSchemaJob.tls.enabled }}
- name: "cassandra-tls-assets"
  projected:
    sources:
    - secret:
        name: {{ template "cassandraSchemaJob.tls.secretName" . }}
        items:
        - key: ca-cert.pem
          path: ca-cert.pem
        - key: client-cert.pem
          path: client-cert.pem
        - key: client-key.pem
          path: client-key.pem
{{- end }}
{{- if and .Values.elasticsearch.client.tls.enabled (not .Values.elasticsearch.client.tls.insecureSkipVerify) }}
- name: "es-tls-assets"
  projected:
    sources:
    - secret:
        name: {{ template "elasticsearch.tls.secretName" . }}
        items:
        - key: ca-cert.pem
          path: ca-cert.pem
        - key: client-cert.pem
          path: client-cert.pem
        - key: client-key.pem
          path: client-key.pem
{{- end }}
{{- if and .Values.remotegRPC.tls.enabled (not .Values.remotegRPC.tls.insecureSkipVerify) }}
- name: "grpc-tls-assets"
  projected:
    sources:
    - secret:
        name: {{ if .Values.remotegRPC.existingSecret }}{{ .Values.remotegRPC.existingSecret }}{{ else }}{{ default "jaeger-remotegrpc-tls-assets" .Values.collector.tlsConfig.newSecretName }}{{- end -}}
        items:
        - key: ca-cert.pem
          path: ca-cert.pem
        - key: client-cert.pem
          path: client-cert.pem
        - key: client-key.pem
          path: client-key.pem
{{- end }}
{{- if or .Values.collector.tlsConfig.otelHttp.enabled
        .Values.collector.tlsConfig.otelgRPC.enabled
        .Values.collector.tlsConfig.jaegerHttp.enabled
        .Values.collector.tlsConfig.jaegergRPC.enabled
        .Values.collector.tlsConfig.zipkin.enabled }}
- name: "http-tls-secret"
  projected:
    sources:
    - secret:
        name: {{ if .Values.collector.tlsConfig.existingSecret }}{{ .Values.collector.tlsConfig.existingSecret }}{{ else }}{{ default "jaeger-collector-tls-secret" .Values.collector.tlsConfig.newSecretName }}{{ end }}
        items:
        - key: ca.crt
          path: ca.crt
        - key: tls.crt
          path: tls.crt
        - key: tls.key
          path: tls.key
{{- end }}
{{- end -}}

{{/*
Generate certificate volume mounts for TLS configuration
*/}}
{{- define "jaeger.certificateVolumeMounts" -}}
{{- if .Values.cassandraSchemaJob.tls.enabled }}
- name: "cassandra-tls-assets"
  mountPath: "/cassandra-tls"
  readOnly: true
{{- end }}
{{- if and .Values.elasticsearch.client.tls.enabled (not .Values.elasticsearch.client.tls.insecureSkipVerify) }}
- name: "es-tls-assets"
  mountPath: "/es-tls"
  readOnly: true
{{- end }}
{{- if and .Values.remotegRPC.tls.enabled (not .Values.remotegRPC.tls.insecureSkipVerify) }}
- name: "grpc-tls-assets"
  mountPath: "/grpc-tls"
  readOnly: true
{{- end }}
{{- if or .Values.collector.tlsConfig.otelHttp.enabled
        .Values.collector.tlsConfig.otelgRPC.enabled
        .Values.collector.tlsConfig.jaegerHttp.enabled
        .Values.collector.tlsConfig.jaegergRPC.enabled
        .Values.collector.tlsConfig.zipkin.enabled }}
- name: "http-tls-secret"
  mountPath: "/http-tls"
  readOnly: true
{{- end }}
{{- end -}}

{{/*
Generate certificate volumes for OpenSearch jobs TLS configuration
*/}}
{{- define "jaeger.opensearchCertificateVolumes" -}}
{{- if and .Values.elasticsearch.client.tls.enabled (not .Values.elasticsearch.client.tls.insecureSkipVerify) }}
- name: "es-tls-assets"
  projected:
    sources:
    - secret:
        name: {{ template "elasticsearch.tls.secretName" . }}
        items:
        - key: ca-cert.pem
          path: ca-cert.pem
        - key: client-cert.pem
          path: client-cert.pem
        - key: client-key.pem
          path: client-key.pem
{{- end }}
{{- end -}}

{{/*
Generate certificate volume mounts for OpenSearch jobs TLS configuration
*/}}
{{- define "jaeger.opensearchCertificateVolumeMounts" -}}
{{- if and .Values.elasticsearch.client.tls.enabled (not .Values.elasticsearch.client.tls.insecureSkipVerify) }}
- name: "es-tls-assets"
  mountPath: "/es-tls"
  readOnly: true
{{- end }}
{{- end -}}

{{/******************************************************************************************************************/}}

{{/*
Generate list of images for tests
*/}}
{{- define "jaeger.monitoredImages" -}}
    {{- if .Values.collector.install -}}
      {{- printf "deployment %s-collector %s %s, " .Values.jaeger.serviceName .Values.collector.name "jaegertracing/jaeger:2.9.0" -}}
      {{- if .Values.readinessProbe.install }}
        {{- printf "deployment %s-collector readiness-probe %s, " .Values.jaeger.serviceName "qubership/jaeger-readiness-probe:0.24.0" -}}
      {{- end -}}
    {{- end -}}
    {{- if .Values.query.install -}}
      {{- printf "deployment %s-query jaeger-query %s, " .Values.jaeger.serviceName "jaegertracing/jaeger:2.9.0" -}}
      {{- if .Values.readinessProbe.install }}
        {{- printf "deployment %s-query readiness-probe %s, " .Values.jaeger.serviceName "qubership/jaeger-readiness-probe:0.24.0" -}}
      {{- end -}}
      {{- if .Values.proxy.install }}
        {{- printf "deployment %s-query proxy %s, " .Values.jaeger.serviceName "envoyproxy/envoy:v1.30.7" -}}
      {{- end -}}
    {{- end -}}
    {{- if .Values.hotrod.install -}}
      {{- printf "deployment %s-hotrod %s %s, " .Values.jaeger.serviceName .Values.hotrod.name "jaegertracing/example-hotrod:1.72.0" -}}
    {{- end -}}
    {{- if .Values.integrationTests.install -}}
      {{- printf "deployment %s %s %s, " .Values.integrationTests.service.name .Values.integrationTests.service.name "qubership/integration-tests" -}}
    {{- end -}}
{{- end -}}

{{/*
Generate custom resource path for integration tests
This path built as "apps/v1/<namespace_name>/deployments/<deployment_name>"
*/}}
{{- define "integrationTests.customResourcePath" -}}
  {{- if .Values.integrationTests.statusWriting.customResourcePath -}}
    {{- .Values.integrationTests.statusWriting.customResourcePath -}}
  {{- else -}}
    {{- printf "apps/v1/%s/deployments/%s" .Release.Namespace .Values.integrationTests.service.name -}}
  {{- end -}}
{{- end -}}

{{/*
Validate duration of cassandraSchemaJob.ttl parameters (trace and dependencies)
*/}}
{{- define "cassandraSchemaJob.validateTTLDuration" -}}
  {{- $val := printf "%v" . }}
  {{- if regexMatch "^0$|^((\\d+h)?(\\d+m)?(\\d+s)?)$" $val }}
    {{- $val }}
  {{- else if regexMatch "^\\d+$" $val }}
    {{- printf "%ss" $val }}
  {{- else }}
    {{- fail (printf "Invalid duration format: %s. Must be a sequence of digits + units (h,m,s)." $val) }}
  {{- end }}
{{- end }}
