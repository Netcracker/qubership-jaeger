*** Variables ***
${secret_name}                  proxy-config
${JAEGER_URL}                   http://jaeger-query.jaeger:16686

*** Settings ***
Resource  ../shared/shared.robot
Suite Setup  Preparation
Library    Process
Library  credentials.py

*** Keywords ***
Restart Jaeger Query Pod
    [Arguments]  ${namespace}
    ${pods}=  Get Pods  ${namespace}
    FOR  ${pod}  IN  @{pods}
        ${name}=  Get From Dictionary  ${pod.metadata}  name
        Run Keyword If  '${name}' starts with 'jaeger-query-'  Delete Pod By Pod Name  ${name}  ${namespace}
    END
    Sleep    60s

*** Test Cases ***
Check Credentials Change and Jaeger Auth
    [Tags]  credentials
    ${response}=  Get Secret  ${secret_name}  ${JAEGER_NAMESPACE}
    Should Be Equal As Strings  ${response.metadata.name}  ${secret_name}
    ${original}=  Convert To String  ${response}
    ${secret}=  Replace Basic Auth Structured  ${original}
    ${patch}=  Patch Secret  ${secret_name}  ${JAEGER_NAMESPACE}  ${secret}
    Restart Jaeger Query Pod  ${JAEGER_NAMESPACE}
    ${result}=  Run Process  curl -s -o /dev/null -w  %%{http_code} -u test1:test1 ${JAEGER_URL}  shell=True
    Should Be Equal As Strings  ${result.stdout}  200
    ${patch}=  Patch Secret  ${secret_name}  ${JAEGER_NAMESPACE}  ${original}
    Restart Jaeger Query Pod  ${JAEGER_NAMESPACE}
