*** Variables ***
${secret_name}                  proxy-config
${JAEGER_URL}                   http://jaeger-query.jaeger:16686

*** Settings ***
Resource  ../shared/shared.robot
Suite Setup  Preparation
Library    Process
Library    credentials.py
Library    OperatingSystem

*** Keywords ***
Restart Jaeger Query Pod
    [Arguments]  ${namespace}
    ${pods}=  Get Pods  ${namespace}
    FOR  ${pod}  IN  @{pods}
        ${name}=  Set Variable  ${pod.metadata.name}
        ${match}=  Run Keyword And Return Status  Should Start With  ${name}  jaeger-query-
        Run Keyword If  ${match}  Delete Pod By Pod Name  ${name}  ${namespace}
    END
    Sleep  60s

*** Test Cases ***
Check Credentials Change and Jaeger Auth
    [Tags]  credentials
    ${response}=  Get Secret  ${secret_name}  ${JAEGER_NAMESPACE}
    ${secret_dict}=  Evaluate  ${response.to_dict()}
    Run Keyword And Ignore Error  Delete From Dictionary  ${secret_dict["metadata"]}  creation_timestamp  resource_version  uid  managed_fields
    Should Be Equal As Strings  ${response.metadata.name}  ${secret_name}
    ${secret}=  Replace Basic Auth Structured  ${response}
    ${patch}=  Patch Secret  ${secret_name}  ${JAEGER_NAMESPACE}  ${secret}
    Restart Jaeger Query Pod  ${JAEGER_NAMESPACE}
    ${result}=    Run Process    curl -s -i -u test1:test1 ${JAEGER_URL}    shell=True
    Should Contain    ${result.stdout}    HTTP/1.1 200
    ${patch}=  Patch Secret  ${secret_name}  ${JAEGER_NAMESPACE}  ${secret_dict}
    Restart Jaeger Query Pod  ${JAEGER_NAMESPACE}
