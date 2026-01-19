*** Variables ***
${OPERATION_RETRY_COUNT}        30x
${OPERATION_RETRY_INTERVAL}     5s
${LOAD_TEST_DURATION}            30s
${MAX_THROUGHPUT_SEARCH_MIN}    100
${MAX_THROUGHPUT_SEARCH_MAX}    2000
${THROUGHPUT_TOLERANCE}          50

*** Settings ***
Resource  ../shared/shared.robot
Suite Setup  Preparation
Library    Process
Library    OperatingSystem
Library    Collections
Library    ../libs/metrics_helper.py

*** Keywords ***
Get Metrics Value
    [Arguments]  ${metric_name}
    [Documentation]  Get metric value from Prometheus metrics endpoint
    ${resp} =  GET On Session  metrics-session  /metrics  timeout=10
    Should Be Equal As Integers  ${resp.status_code}  200
    ${sum} =  Get Metric Sum  ${resp.text}  ${metric_name}
    RETURN  ${sum}

Get Dropped Spans Count
    ${value} =  Get Metrics Value  otelcol_processor_refused_spans_total
    RETURN  ${value}

Get Received Spans Count
    ${value} =  Get Metrics Value  otelcol_receiver_accepted_spans_total
    RETURN  ${value}

Generate Load At Rate
    [Arguments]  ${spans_per_second}  ${duration}=${LOAD_TEST_DURATION}
    [Documentation]  Generate load using tracegen
    ...  IMPORTANT: When --duration is provided, tracegen IGNORES --traces and runs at maximum speed.
    ...  This means we cannot directly control the rate using --traces + --duration.
    ...  Instead, we calculate the total number of traces needed and use --traces alone (no --duration).
    ...  Each trace contains 1 span by default, so total_traces = spans_per_second * duration_seconds
    ${duration_seconds} =  Evaluate  int('${duration}'.replace('s', ''))
    ${total_traces} =  Evaluate  int(${spans_per_second} * ${duration_seconds})
    ${collector_endpoint} =  Set Variable  ${JAEGER_SERVICE_NAME}-collector.${JAEGER_NAMESPACE}:4317
    Log To Console  Generating ${total_traces} traces (target: ${spans_per_second} spans/sec for ${duration})
    Log To Console  Note: tracegen will generate at maximum speed. Actual rate will be measured via metrics.
    # Use --traces without --duration to generate exact number of traces
    # --spans 1 ensures each trace has 1 span (default, but explicit)
    # --workers 1 ensures single worker (default, but explicit for predictable behavior)
    ${cmd} =  Set Variable  export OTEL_EXPORTER_OTLP_ENDPOINT=http://${collector_endpoint} && tracegen --traces ${total_traces} --spans 1 --workers 1 --trace-exporter otlp-grpc
    ${result} =  Run Process  ${cmd}  shell=True  timeout=${duration_seconds + 120}s
    IF  ${result.rc} != 0
        Fail  Tracegen failed: ${result.stderr}
    END
    Log To Console  Tracegen completed successfully

Test Throughput For Drops
    [Arguments]  ${spans_per_second}
    [Documentation]  Test if a given throughput causes drops. Returns True if no drops, False if drops occur.
    # Wait a bit to ensure system is stable from previous test
    Sleep  5s

    # Get initial counts
    ${initial_dropped} =  Get Dropped Spans Count
    ${initial_received} =  Get Received Spans Count
    Log To Console  [Before] Initial dropped: ${initial_dropped}, received: ${initial_received}

    # Generate load using keyword from memory_limiter.robot
    Generate Load At Rate  ${spans_per_second}  ${LOAD_TEST_DURATION}

    # Wait for processing to complete (allow time for spans to be processed and metrics to update)
    Sleep  10s

    # Get final counts
    ${final_dropped} =  Get Dropped Spans Count
    ${final_received} =  Get Received Spans Count
    Log To Console  [After] Final dropped: ${final_dropped}, received: ${final_received}

    ${dropped_delta} =  Evaluate  ${final_dropped} - ${initial_dropped}
    ${received_delta} =  Evaluate  ${final_received} - ${initial_received}
    ${duration_seconds} =  Evaluate  int('${LOAD_TEST_DURATION}'.replace('s', ''))
    ${expected_spans} =  Evaluate  ${spans_per_second} * ${duration_seconds}
    ${actual_rate} =  Evaluate  ${received_delta} / ${duration_seconds} if ${duration_seconds} > 0 else 0.0
    ${actual_rate_rounded} =  Evaluate  round(${actual_rate}, 2)

    Log To Console  Throughput ${spans_per_second} spans/sec: dropped_delta=${dropped_delta}, received_delta=${received_delta}, expected=${expected_spans}, actual_rate=${actual_rate_rounded} spans/sec

    # Return True if no drops (or very minimal drops within tolerance)
    IF  ${dropped_delta} <= 0
        RETURN  ${True}
    ELSE
        RETURN  ${False}
    END

Find Maximum Throughput Binary Search
    [Documentation]  Use binary search to find maximum throughput with no drops
    ${min_throughput} =  Set Variable  ${MAX_THROUGHPUT_SEARCH_MIN}
    ${max_throughput} =  Set Variable  ${MAX_THROUGHPUT_SEARCH_MAX}
    ${current_max} =  Set Variable  ${0}

    Log To Console  Starting binary search for maximum throughput without drops
    Log To Console  Search range: ${min_throughput} - ${max_throughput} spans/sec

    WHILE  ${max_throughput} - ${min_throughput} > ${THROUGHPUT_TOLERANCE}
        ${test_throughput} =  Evaluate  int((${min_throughput} + ${max_throughput}) / 2)
        Log To Console  Testing throughput: ${test_throughput} spans/sec (range: ${min_throughput}-${max_throughput})

        ${no_drops} =  Test Throughput For Drops  ${test_throughput}

        IF  ${no_drops}
            Log To Console  ✓ No drops at ${test_throughput} spans/sec
            ${current_max} =  Set Variable  ${test_throughput}
            ${min_throughput} =  Set Variable  ${test_throughput}
        ELSE
            Log To Console  ✗ Drops detected at ${test_throughput} spans/sec
            ${max_throughput} =  Set Variable  ${test_throughput}
        END

        # Wait a bit between tests to let system stabilize
        Sleep  5s
    END

    Log To Console  Maximum throughput without drops: ~${current_max} spans/sec
    RETURN  ${current_max}

Find Maximum Throughput Linear Search
    [Arguments]  ${start_throughput}=100  ${increment}=50  ${max_throughput}=2000
    [Documentation]  Linearly increase throughput until drops are detected
    ${current_throughput} =  Set Variable  ${start_throughput}
    ${last_successful} =  Set Variable  ${0}

    Log To Console  Starting linear search for maximum throughput without drops
    Log To Console  Starting at ${start_throughput} spans/sec, incrementing by ${increment}

    WHILE  ${current_throughput} <= ${max_throughput}
        Log To Console  Testing throughput: ${current_throughput} spans/sec

        ${no_drops} =  Test Throughput For Drops  ${current_throughput}

        IF  ${no_drops}
            Log To Console  ✓ No drops at ${current_throughput} spans/sec
            ${last_successful} =  Set Variable  ${current_throughput}
            ${current_throughput} =  Evaluate  ${current_throughput} + ${increment}
        ELSE
            Log To Console  ✗ Drops detected at ${current_throughput} spans/sec
            Log To Console  Maximum throughput without drops: ${last_successful} spans/sec
            RETURN  ${last_successful}
        END

        # Wait a bit between tests
        Sleep  5s
    END

    Log To Console  Maximum throughput without drops: ${last_successful} spans/sec (reached max test limit)
    RETURN  ${last_successful}

*** Test Cases ***
Find Maximum Throughput Linear
    [Tags]  experimental
    [Documentation]  Experimentally find maximum throughput without drops using linear search
    ...  This test gradually increases throughput until drops are detected
    ${max_throughput} =  Find Maximum Throughput Linear Search  start_throughput=100  increment=50  max_throughput=2000
    Log To Console  ==========================================
    Log To Console  RESULT: Maximum throughput without drops = ${max_throughput} spans/sec
    Log To Console  ==========================================
    Should Be True  ${max_throughput} > 0  Failed to find any throughput without drops

Find Maximum Throughput Binary Search
    [Tags]  experimental
    [Documentation]  Experimentally find maximum throughput without drops using binary search
    ...  This test uses binary search for faster convergence
    ${max_throughput} =  Find Maximum Throughput Binary Search
    Log To Console  ==========================================
    Log To Console  RESULT: Maximum throughput without drops = ${max_throughput} spans/sec
    Log To Console  ==========================================
    Should Be True  ${max_throughput} > 0  Failed to find any throughput without drops

