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
        Log To Console  ======== INSPECTING POD =========
        Log To Console  ${pod.metadata.name}
        ${name}=  Set Variable  ${pod.metadata.name}
        ${match}=  Run Keyword And Return Status  Should Start With  ${name}  jaeger-query-
        Run Keyword If  ${match}  Delete Pod By Pod Name  ${name}  ${namespace}
    END
    Sleep  60s

*** Test Cases ***
Check Credentials Change and Jaeger Auth
    [Tags]  credentials

    Log To Console  \n[ROBOT] Получаем секрет из Kubernetes...
    ${response}=  Get Secret  ${secret_name}  ${JAEGER_NAMESPACE}

    Should Be Equal As Strings  ${response.metadata.name}  ${secret_name}

    Log To Console  \n[ROBOT] Заменяем логин:пароль в config.yaml...
    ${secret}=  Replace Basic Auth Structured  ${response}

    Log To Console  \n[ROBOT] Новый секрет подготовлен. Логирую результат:
    Log  ${secret}  console=True

    ${patch}=  Patch Secret  ${secret_name}  ${JAEGER_NAMESPACE}  ${secret}

    Log To Console  \n[ROBOT] Перезапускаем Jaeger-под...
    Log  restart  console=True
    Restart Jaeger Query Pod  ${JAEGER_NAMESPACE}

    Log To Console  \n[ROBOT] Проверяем доступ по test1:test1...
    ${result}=  Run Process  curl  -s  -o  /dev/null  -w  %{http_code}  -u  test1:test1  ${JAEGER_URL}
    Should Be Equal As Strings  ${result.stdout}  200

    Log To Console  \n[ROBOT] Возвращаем старый секрет...
    ${patch}=  Patch Secret  ${secret_name}  ${JAEGER_NAMESPACE}  ${original}
    Restart Jaeger Query Pod  ${JAEGER_NAMESPACE}