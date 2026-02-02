*** Variables ***
${OPERATION_RETRY_COUNT}        30x
${OPERATION_RETRY_INTERVAL}     5s

*** Settings ***
Resource  ../shared/shared.robot
Suite Setup  Preparation


*** Test Cases ***
Check Deployments
    [Tags]  smoke
    Check Inactive Deployments

Check Collector Pods Are Running
    [Tags]  smoke
    Wait Until Keyword Succeeds  ${OPERATION_RETRY_COUNT}  ${OPERATION_RETRY_INTERVAL}
    ...  Check Collector Pods

Check Query Pods Are Running
    [Tags]  smoke
    Wait Until Keyword Succeeds  ${OPERATION_RETRY_COUNT}  ${OPERATION_RETRY_INTERVAL}
    ...  Check Query Pod

Jaeger can serve spans
    [Tags]  smoke
    Wait Until Keyword Succeeds  ${OPERATION_RETRY_COUNT}  ${OPERATION_RETRY_INTERVAL}
    ...  Check Jaeger Alive
    ${trace} =  JaegerLibrary.generate_trace
    Post Random Spans  ${trace}
    Get Trace From Jaeger With Attempts  ${trace[0]['traceId']}
