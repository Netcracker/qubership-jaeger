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
    [Arguments]  ${traces_per_second}  ${duration}=${LOAD_TEST_DURATION}
    [Documentation]  Generate load using tracegen with rate limiting
    ...  Sends traces in batches with delays to approximate the target rate, preventing memory spikes.
    ...  Each trace contains 2 spans (tracegen default), so spans/sec = traces_per_second * 2.
    ...  total_traces = traces_per_second * duration_seconds
    ${duration_seconds} =  Evaluate  int('${duration}'.replace('s', ''))
    ${total_traces} =  Evaluate  int(${traces_per_second} * ${duration_seconds})
    ${total_spans} =  Evaluate  ${total_traces} * 2  # Each trace has 2 spans
    ${spans_per_second} =  Evaluate  ${traces_per_second} * 2  # Each trace has 2 spans
    ${collector_endpoint} =  Set Variable  ${JAEGER_SERVICE_NAME}-collector.${JAEGER_NAMESPACE}:4317

    # Rate-limited mode: send in batches with delays to achieve target rate
    # Calculate batch size: larger batches reduce overhead, but smaller batches give smoother rate
    # Use ~2 batches per second for smoother rate control
    ${batch_size} =  Evaluate  max(100, int(${traces_per_second} / 2))  # ~2 batches per second
    # Calculate delay between batches to achieve target rate
    # Each batch has batch_size traces = batch_size * 2 spans (each trace has 2 spans)
    # Target: traces_per_second traces/sec = spans_per_second spans/sec
    # So: delay = (batch_size * 2) / spans_per_second seconds
    ${batch_delay} =  Evaluate  (${batch_size} * 2.0) / ${spans_per_second}
    ${num_batches} =  Evaluate  int((${total_traces} + ${batch_size} - 1) / ${batch_size})  # Ceiling division
    ${batch_delay_formatted} =  Evaluate  '{:.3f}'.format(${batch_delay})

    Log To Console  Generating ${total_traces} traces (${total_spans} spans total, target: ${traces_per_second} traces/sec = ${spans_per_second} spans/sec for ${duration}) with rate limiting
    Log To Console  Rate limiting: batch_size=${batch_size}, batches=${num_batches}, delay=${batch_delay_formatted}s between batches

    # Send in batches with delays
    ${remaining_traces} =  Set Variable  ${total_traces}
    FOR  ${batch_num}  IN RANGE  1  ${num_batches} + 1
        ${current_batch_size} =  Evaluate  min(${batch_size}, ${remaining_traces})
        ${cmd} =  Set Variable  export OTEL_EXPORTER_OTLP_ENDPOINT=http://${collector_endpoint} && tracegen --traces ${current_batch_size} --trace-exporter otlp-grpc
        # Estimate timeout: allow time for this batch plus some buffer
        ${batch_timeout} =  Evaluate  max(int(${current_batch_size} / 10), 30)  # At least 30s, or 0.1s per trace
        ${result} =  Run Process  ${cmd}  shell=True  timeout=${batch_timeout}s
        IF  ${result.rc} != 0
            Fail  Tracegen failed to generate batch ${batch_num}/${num_batches} (exit code ${result.rc}). stdout: ${result.stdout}. stderr: ${result.stderr}
        END
        ${remaining_traces} =  Evaluate  ${remaining_traces} - ${current_batch_size}
        # Sleep between batches (except after the last batch)
        IF  ${batch_num} < ${num_batches}
            Sleep  ${batch_delay}s
        END
    END
    Log To Console  Tracegen completed successfully (all ${num_batches} batches sent)

Test Throughput For Drops
    [Arguments]  ${traces_per_second}
    [Documentation]  Test if a given throughput causes drops. Returns True if no drops, False if drops occur.
    ...  Note: Each trace contains 2 spans (tracegen default), so spans/sec = traces_per_second * 2.
    # Wait a bit to ensure system is stable from previous test
    Sleep  5s

    # Get initial counts
    ${initial_dropped} =  Get Dropped Spans Count
    ${initial_received} =  Get Received Spans Count
    Log To Console  [Before] Initial dropped: ${initial_dropped}, received: ${initial_received}

    # Calculate spans/sec (each trace has 2 spans)
    ${spans_per_second} =  Evaluate  ${traces_per_second} * 2

    # Generate load (traces_per_second traces/sec = spans_per_second spans/sec since each trace = 2 spans)
    Generate Load At Rate  ${traces_per_second}  ${LOAD_TEST_DURATION}

    # Wait for processing to complete (allow time for spans to be processed and metrics to update)
    Sleep  10s

    # Get final counts
    ${final_dropped} =  Get Dropped Spans Count
    ${final_received} =  Get Received Spans Count
    Log To Console  [After] Final dropped: ${final_dropped}, received: ${final_received}

    ${dropped_delta} =  Evaluate  ${final_dropped} - ${initial_dropped}
    ${received_delta} =  Evaluate  ${final_received} - ${initial_received}
    ${duration_seconds} =  Evaluate  int('${LOAD_TEST_DURATION}'.replace('s', ''))
    # Expected spans = traces_per_second * 2 * duration (since each trace = 2 spans)
    ${expected_spans} =  Evaluate  ${traces_per_second} * 2 * ${duration_seconds}
    ${actual_rate} =  Evaluate  ${received_delta} / ${duration_seconds} if ${duration_seconds} > 0 else 0.0
    ${actual_rate_rounded} =  Evaluate  round(${actual_rate}, 2)

    Log To Console  Throughput ${traces_per_second} traces/sec (${spans_per_second} spans/sec): dropped_delta=${dropped_delta}, received_delta=${received_delta}, expected=${expected_spans} spans, actual_rate=${actual_rate_rounded} spans/sec

    # Return True if no drops (or very minimal drops within tolerance)
    IF  ${dropped_delta} <= 0
        RETURN  ${True}
    ELSE
        RETURN  ${False}
    END

Find Maximum Throughput Binary Search
    [Documentation]  Use binary search to find maximum throughput with no drops
    ...  Note: throughput values are in traces/sec. Each trace contains 2 spans, so spans/sec = traces/sec * 2
    ${min_throughput} =  Set Variable  ${MAX_THROUGHPUT_SEARCH_MIN}
    ${max_throughput} =  Set Variable  ${MAX_THROUGHPUT_SEARCH_MAX}
    ${current_max} =  Set Variable  ${0}

    Log To Console  Starting binary search for maximum throughput without drops
    ${min_spans_per_sec} =  Evaluate  ${min_throughput} * 2
    ${max_spans_per_sec} =  Evaluate  ${max_throughput} * 2
    Log To Console  Search range: ${min_throughput} - ${max_throughput} traces/sec (${min_spans_per_sec} - ${max_spans_per_sec} spans/sec)

    WHILE  ${max_throughput} - ${min_throughput} > ${THROUGHPUT_TOLERANCE}
        ${test_throughput} =  Evaluate  int((${min_throughput} + ${max_throughput}) / 2)
        ${test_spans_per_sec} =  Evaluate  ${test_throughput} * 2
        Log To Console  Testing throughput: ${test_throughput} traces/sec (${test_spans_per_sec} spans/sec) (range: ${min_throughput}-${max_throughput} traces/sec)

        ${no_drops} =  Test Throughput For Drops  ${test_throughput}

        IF  ${no_drops}
            Log To Console  ✓ No drops at ${test_throughput} traces/sec (${test_spans_per_sec} spans/sec)
            ${current_max} =  Set Variable  ${test_throughput}
            ${min_throughput} =  Set Variable  ${test_throughput}
        ELSE
            Log To Console  ✗ Drops detected at ${test_throughput} traces/sec (${test_spans_per_sec} spans/sec)
            ${max_throughput} =  Set Variable  ${test_throughput}
        END

        # Wait a bit between tests to let system stabilize
        Sleep  5s
    END

    ${current_max_spans} =  Evaluate  ${current_max} * 2
    Log To Console  Maximum throughput without drops: ~${current_max} traces/sec (${current_max_spans} spans/sec)
    RETURN  ${current_max}

Find Maximum Throughput Linear Search
    [Arguments]  ${start_throughput}=100  ${increment}=50  ${max_throughput}=2000
    [Documentation]  Linearly increase throughput until drops are detected
    ${current_throughput} =  Set Variable  ${start_throughput}
    ${last_successful} =  Set Variable  ${0}

    Log To Console  Starting linear search for maximum throughput without drops
    Log To Console  Starting at ${start_throughput} traces/sec (${start_throughput} spans/sec), incrementing by ${increment}

    WHILE  ${current_throughput} <= ${max_throughput}
        Log To Console  Testing throughput: ${current_throughput} traces/sec (${current_throughput} spans/sec)

        ${no_drops} =  Test Throughput For Drops  ${current_throughput}

        IF  ${no_drops}
            Log To Console  ✓ No drops at ${current_throughput} traces/sec (${current_throughput} spans/sec)
            ${last_successful} =  Set Variable  ${current_throughput}
            ${current_throughput} =  Evaluate  ${current_throughput} + ${increment}
        ELSE
            Log To Console  ✗ Drops detected at ${current_throughput} traces/sec (${current_throughput} spans/sec)
            Log To Console  Maximum throughput without drops: ${last_successful} traces/sec (${last_successful} spans/sec)
            RETURN  ${last_successful}
        END

        # Wait a bit between tests
        Sleep  5s
    END

    Log To Console  Maximum throughput without drops: ${last_successful} traces/sec (${last_successful} spans/sec) (reached max test limit)
    RETURN  ${last_successful}

*** Test Cases ***
Find Maximum Throughput Linear
    [Tags]  experimental
    [Documentation]  Experimentally find maximum throughput without drops using linear search
    ...  This test gradually increases throughput until drops are detected.
    ...  Note: Values are in traces/sec. Each trace contains 2 spans, so spans/sec = traces/sec * 2.
    ${max_throughput} =  Find Maximum Throughput Linear Search  start_throughput=100  increment=50  max_throughput=2000
    ${max_spans_per_sec} =  Evaluate  ${max_throughput} * 2
    Log To Console  ==========================================
    Log To Console  RESULT: Maximum throughput without drops = ${max_throughput} traces/sec (${max_spans_per_sec} spans/sec)
    Log To Console  ==========================================
    Should Be True  ${max_throughput} > 0  Failed to find any throughput without drops

Find Maximum Throughput Binary Search
    [Tags]  experimental
    [Documentation]  Experimentally find maximum throughput without drops using binary search
    ...  This test uses binary search for faster convergence.
    ...  Note: Values are in traces/sec. Each trace contains 2 spans, so spans/sec = traces/sec * 2.
    ${max_throughput} =  Find Maximum Throughput Binary Search
    ${max_spans_per_sec} =  Evaluate  ${max_throughput} * 2
    Log To Console  ==========================================
    Log To Console  RESULT: Maximum throughput without drops = ${max_throughput} traces/sec (${max_spans_per_sec} spans/sec)
    Log To Console  ==========================================
    Should Be True  ${max_throughput} > 0  Failed to find any throughput without drops

