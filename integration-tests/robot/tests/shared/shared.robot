*** Variables ***
${JAEGER_NAMESPACE}            %{JAEGER_NAMESPACE}
${JAEGER_SERVICE_NAME}         %{JAEGER_SERVICE_NAME}
${MANAGED_BY_OPERATOR}         true
${COUNT_OF_RETRY}              20x
${RETRY_INTERVAL}              5s
${COUNT_OF_RETRY_FOR_TRACE}    10x
${RETRY_INTERVAL_FOR_TRACE}    2s
${GENERATE_COUNT}              %{GENERATE_COUNT}
${LINK_FOR_GENERATOR}          %{LINK_FOR_GENERATOR}
${WAITING_TIME}                %{WAITING_TIME}


*** Settings ***
Library  String
Library	 Collections
Library	 RequestsLibrary
Library  PlatformLibrary  managed_by_operator=${MANAGED_BY_OPERATOR}
Library  ../libs/JaegerLibrary.py


*** Keywords ***
Preparation
    ${headers} =  Create Dictionary  Content-Type=application/json
    Set Global Variable  ${headers}
    Create Session    jaeger-query-session    http://${JAEGER_SERVICE_NAME}-query.${JAEGER_NAMESPACE}:16686
    Create Session    jaeger-collector-session    http://${JAEGER_SERVICE_NAME}-collector.${JAEGER_NAMESPACE}:9411
    Create Session    healthcheck    http://${JAEGER_SERVICE_NAME}-collector.${JAEGER_NAMESPACE}:13133
    Create Session    for-generator    ${LINK_FOR_GENERATOR}
    Create Session    metrics-session    http://${JAEGER_SERVICE_NAME}-collector.${JAEGER_NAMESPACE}:8888

Convert Json ${json} To Type
    ${json_dictionary} =  Evaluate  json.loads('''${json}''')  json
    RETURN  ${json_dictionary}

Check Inactive Deployments
    ${count_inactive_collectors} =  Get Inactive Deployment Entities Count For Service  ${JAEGER_NAMESPACE}  ${JAEGER_SERVICE_NAME}-collector
    ${count_inactive_query} =  Get Inactive Deployment Entities Count For Service  ${JAEGER_NAMESPACE}  ${JAEGER_SERVICE_NAME}-query
    Should Be Equal  ${count_inactive_collectors}  ${0}  Found Inactive Collectors
    Should Be Equal  ${count_inactive_query}  ${0}  Found Inactive Query

Check Deployment State
    [Arguments]  ${name}
    ${deployments_in_namespace} =  Get Active Deployment Entities For Service  ${JAEGER_NAMESPACE}  ${name}  label=app.kubernetes.io/name
    ${list_len}=  Get Length  ${deployments_in_namespace}
    ${flag} =  Run Keyword And Return Status  Should Be True  ${list_len} != 0
    RETURN  ${flag}

Check Jaeger Alive
    ${resp} =  GET On Session  healthcheck  /status  timeout=10
    Should Be Equal As Integers  ${resp.status_code}   200
    ${resp_json} =  Convert Json ${resp.content} To Type
    Dictionary Should Contain Value  ${resp_json}  StatusOK

Post Random Spans
    [Arguments]  ${trace}
    ${json_trace}=  Evaluate  json.dumps(${trace})  json
    ${resp} =  POST On Session  jaeger-collector-session  /api/v2/spans  data=${json_trace}  headers=${headers}  timeout=30
    Should Be Equal As Strings  ${resp.status_code}   202
    Log To Console  \nSpan was add to Jaeger

Post Random Spans As Generator
    [Arguments]  ${trace}
    ${json_trace}=  Evaluate  json.dumps(${trace})  json
    ${resp} =  POST On Session  for-generator  /api/v2/spans  data=${json_trace}  headers=${headers}  timeout=30
    Should Be Equal As Strings  ${resp.status_code}   202
    Log To Console  \nSpan was add to Jaeger

Get Trace From Jaeger
    [Arguments]  ${traceId}
    ${resp} =  GET On Session  jaeger-query-session  /api/traces/${traceId}  timeout=10
    Should Be Equal As Strings  ${resp.status_code}   200
    ${services} =  GET On Session  jaeger-query-session  /api/services  timeout=10
    Should Be Equal As Strings  ${services.status_code}   200
    ${service_dict} =  Convert Json ${services.content} To Type
    Should Contain  ${service_dict['data']}  first_service

Get Trace From Jaeger With Attempts
    [Arguments]  ${traceId}
    Wait Until Keyword Succeeds  ${COUNT_OF_RETRY_FOR_TRACE}  ${RETRY_INTERVAL_FOR_TRACE}
    ...  Get Trace From Jaeger  ${traceId}

Check Query Pod
    ${pods_running} =  Check Deployment State  ${JAEGER_SERVICE_NAME}-query
    Should Be True  ${pods_running} == True

Check Collector Pods
    ${pods_running} =  Check Deployment State  ${JAEGER_SERVICE_NAME}-collector
    Should Be True  ${pods_running} == True

Get List Pod Names For Deployment Entity
    [Arguments]  ${component}
    @{list_pods} =  Get Pod Names For Deployment Entity  ${JAEGER_SERVICE_NAME}-${component}  ${JAEGER_NAMESPACE}
    Log to console  LIST_PODS on Deployment: @{list_pods}
    Set Suite Variable  @{list_pods}

Get Active Deployment Replicas
    [Arguments]  ${component}
    ${ACTIVE_POD} =  Get Length  ${list_pods}
    Log to console  Find ${component} pod: ${ACTIVE_POD}
    Set Suite Variable  ${ACTIVE_POD}
