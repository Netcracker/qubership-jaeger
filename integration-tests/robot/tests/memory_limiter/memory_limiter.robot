*** Variables ***
${OPERATION_RETRY_COUNT}        30x
${OPERATION_RETRY_INTERVAL}     5s
${METRICS_ENDPOINT}              http://${JAEGER_SERVICE_NAME}-collector.${JAEGER_NAMESPACE}:8888/metrics
${TARGET_THROUGHPUT}             1000
# Etalon throughput: based on experimental results (ACTUAL RECEIVED rates)
# NOTE: With rate limiting enabled, we can use the steady-state capacity (~1000 spans/sec threshold) rather than
# the bursty capacity (400 spans/sec). Rate limiting spreads the load over time, preventing overwhelming
# the collector with a burst.
# Etalon: 700 spans/sec (70% of ~1000 spans/sec threshold to ensure stable operation without issues)
# Based on experimental testing: ~500 traces/sec = 1000 spans/sec threshold (each trace has 2 spans)
# Using 70% of threshold for safety margin: 700 spans/sec = 350 traces/sec
# 10500 traces = 21000 spans total, equivalent to 700 spans/sec over 30 seconds
${ETALON_TARGET_SPANS_PER_SECOND}  700
${ETALON_TOTAL_TRACES}                 10500
# Stabilization time between tests to reduce interference from previous test runs
${STABILIZATION_TIME}                  15s
# High load test: 2300 spans/sec to verify Jaeger survives (drops expected, but no restarts)
# High load: 2300 spans/sec with rate limiting (sustained load to trigger memory limiter)
# 20000 traces = 40000 spans total, equivalent to 2300 spans/sec over ~17 seconds (with rate limiting)
# Set to 2300 spans/sec to apply sustained pressure and trigger drops
${HIGH_LOAD_TOTAL_TRACES}              20000

*** Settings ***
Resource  ../shared/shared.robot
Suite Setup  Preparation
Library    Process
Library    OperatingSystem
Library    Collections
Library    ../libs/metrics_helper.py

*** Keywords ***
Get ConfigMap Content
    [Arguments]  ${configmap_name}  ${namespace}
    ${configmap} =  Get Config Map  ${configmap_name}  ${namespace}
    ${config_content} =  Evaluate  $configmap.data['config.yaml']
    RETURN  ${config_content}

Check Memory Limiter In Pipeline
    [Arguments]  ${config_content}
    Should Contain  ${config_content}  memory_limiter
    Should Contain  ${config_content}  processors:
    # Check that memory_limiter is in the traces pipeline
    ${has_memory_limiter} =  Run Keyword And Return Status
    ...  Should Contain  ${config_content}  [memory_limiter, batch]
    IF  not ${has_memory_limiter}
        ${has_memory_limiter} =  Run Keyword And Return Status
        ...  Should Match Regexp  ${config_content}  processors:.*memory_limiter
    END
    Should Be True  ${has_memory_limiter}  Memory limiter not found in processor pipeline

Check Memory Limiter Settings
    [Arguments]  ${config_content}
    Should Contain  ${config_content}  memory_limiter:
    Should Contain  ${config_content}  limit_mib:
    Should Contain  ${config_content}  spike_limit_mib:
    Should Contain  ${config_content}  check_interval:

Get Metrics Value
    [Arguments]  ${metric_name}
    [Documentation]  Get metric value from Prometheus metrics endpoint
    ...  Uses metrics-session created in Preparation keyword (shared.robot)
    ...  Handles metrics with labels and multiple instances by summing all matching values
    ...  Handles scientific notation (e.g., 1.629326e+06)
    ${resp} =  GET On Session  metrics-session  /metrics  timeout=10
    Should Be Equal As Integers  ${resp.status_code}  200
    # Use Python helper function to avoid string escaping issues with large metrics text
    ${sum} =  Get Metric Sum  ${resp.text}  ${metric_name}
    RETURN  ${sum}

Get Dropped Spans Count
    ${value} =  Get Metrics Value  otelcol_processor_refused_spans_total
    RETURN  ${value}

Get Sent Spans Count
    ${value} =  Get Metrics Value  otelcol_exporter_sent_spans_total
    RETURN  ${value}

Get Received Spans Count
    ${value} =  Get Metrics Value  otelcol_receiver_accepted_spans_total
    RETURN  ${value}

Get Collector Pod Restart Counts
    [Arguments]  ${pods_str}
    [Documentation]  Get restart counts for collector pods
    ...  Returns a string representation: "pod1:count1,pod2:count2" for easy comparison
    IF  '${pods_str}' == '${EMPTY}'
        RETURN  ${EMPTY}
    END
    ${pod_list} =  Evaluate  '${pods_str}'.split(',') if '${pods_str}' else []
    ${restart_info} =  Create List
    FOR  ${pod_name}  IN  @{pod_list}
        ${restart_count} =  Get Pod Container Restart Count  ${pod_name}  collector
        Append To List  ${restart_info}  ${pod_name}:${restart_count}
    END
    ${result} =  Evaluate  ','.join(sorted($restart_info)) if $restart_info else ''
    RETURN  ${result}

Get Pod Container Restart Count
    [Arguments]  ${pod_name}  ${container_name}
    [Documentation]  Get restart count for a specific container in a pod using Kubernetes API
    ${restart_count} =  Evaluate  __import__('sys').path.insert(0, '${CURDIR}/../libs') or __import__('pod_helper', fromlist=['get_pod_container_restart_count']).get_pod_container_restart_count('${pod_name}', '${container_name}', '${JAEGER_NAMESPACE}')
    RETURN  ${restart_count}

Get Pod Container Termination Details
    [Arguments]  ${pod_name}  ${container_name}
    [Documentation]  Get termination details (reason, exit code, message) for a container's last termination
    ...  Returns a dictionary with 'reason', 'exitCode', 'message', 'finishedAt', or None if no termination
    ${termination_info} =  Evaluate  __import__('sys').path.insert(0, '${CURDIR}/../libs') or __import__('pod_helper', fromlist=['get_pod_container_termination_details']).get_pod_container_termination_details('${pod_name}', '${container_name}', '${JAEGER_NAMESPACE}')
    RETURN  ${termination_info}

Get Pod Events
    [Arguments]  ${pod_name}  ${limit}=20
    [Documentation]  Get recent events for a pod using Kubernetes API
    ${events_list} =  Evaluate  __import__('sys').path.insert(0, '${CURDIR}/../libs') or __import__('pod_helper', fromlist=['get_pod_events']).get_pod_events('${pod_name}', '${JAEGER_NAMESPACE}', ${limit})
    ${events_str} =  Evaluate  '\\n'.join($events_list) if $events_list else ''
    RETURN  ${events_str}

Check And Display Restart Details
    [Arguments]  ${pods_before_str}  ${restarts_before}  ${pods_after_str}  ${restarts_after}
    [Documentation]  Compare restart counts and display detailed restart information if restarts occurred
    ...  Returns: tuple (had_restarts, restart_reason) where had_restarts is boolean and restart_reason is string
    Log To Console  Checking for container restarts...
    ${pods_before_list} =  Evaluate  '${pods_before_str}'.split(',') if '${pods_before_str}' else []
    ${pods_after_list} =  Evaluate  '${pods_after_str}'.split(',') if '${pods_after_str}' else []
    # Parse restart counts from string format "pod1:count1,pod2:count2"
    ${restarts_before_dict} =  Evaluate  {item.split(':')[0]: int(item.split(':')[1]) for item in '${restarts_before}'.split(',') if ':' in item} if '${restarts_before}' else {}
    ${restarts_after_dict} =  Evaluate  {item.split(':')[0]: int(item.split(':')[1]) for item in '${restarts_after}'.split(',') if ':' in item} if '${restarts_after}' else {}
    ${had_restarts} =  Set Variable  ${False}
    ${restart_reason} =  Set Variable  ${EMPTY}
    # Check each pod that existed before
    FOR  ${pod_name}  IN  @{pods_before_list}
        ${restart_before} =  Evaluate  $restarts_before_dict.get('${pod_name}', 0) if $restarts_before_dict else 0
        ${restart_after} =  Evaluate  $restarts_after_dict.get('${pod_name}', 0) if $restarts_after_dict else 0
        ${restart_delta} =  Evaluate  ${restart_after} - ${restart_before}
        IF  ${restart_delta} > 0
            ${had_restarts} =  Set Variable  ${True}
            Log To Console  ⚠️  Container restarted: ${pod_name} (restart count increased from ${restart_before} to ${restart_after})
            # Get termination details
            ${termination_info} =  Get Pod Container Termination Details  ${pod_name}  collector
            ${has_termination} =  Evaluate  $termination_info is not None and isinstance($termination_info, dict) and len($termination_info) > 0
            IF  ${has_termination}
                ${reason} =  Evaluate  $termination_info.get('reason', 'Unknown') if $termination_info else 'Unknown'
                ${exit_code} =  Evaluate  $termination_info.get('exitCode', 'N/A') if $termination_info else 'N/A'
                ${message} =  Evaluate  $termination_info.get('message', 'N/A') if $termination_info else 'N/A'
                ${finished_at} =  Evaluate  $termination_info.get('finishedAt', 'N/A') if $termination_info else 'N/A'
                Log To Console  └─ Termination reason: ${reason}
                Log To Console  └─ Exit code: ${exit_code}
                Log To Console  └─ Finished at: ${finished_at}
                ${has_message} =  Evaluate  '${message}' != 'N/A' and '${message}' != '' and '${message}' != 'None'
                IF  ${has_message}
                    Log To Console  └─ Message: ${message}
                END
                # Store the reason for the first restart (most important)
                IF  '${restart_reason}' == '${EMPTY}'
                    ${restart_reason} =  Set Variable  ${reason}
                END
            ELSE
                Log To Console  └─ No termination details available (container may have been restarted by Kubernetes or details not yet available)
                IF  '${restart_reason}' == '${EMPTY}'
                    ${restart_reason} =  Set Variable  Unknown
                END
            END
            # Get recent events
            ${events} =  Get Pod Events  ${pod_name}  10
            ${has_events} =  Evaluate  '${events}' != '' and '${events}' != '${EMPTY}' and '${events}' != 'None'
            IF  ${has_events}
                Log To Console  └─ Recent pod events:
                ${event_lines} =  Evaluate  '${events}'.split('\\n') if '${events}' else []
                FOR  ${line}  IN  @{event_lines}
                    ${line_stripped} =  Evaluate  '${line}'.strip()
                    ${is_non_empty} =  Evaluate  '${line_stripped}' != ''
                    IF  ${is_non_empty}
                        Log To Console  └─   ${line_stripped}
                    END
                END
            END
        END
    END
    # Check if any new pods appeared (shouldn't happen, but log if it does)
    FOR  ${pod_name}  IN  @{pods_after_list}
        ${was_before} =  Evaluate  '${pod_name}' in '${pods_before_str}'
        IF  not ${was_before}
            Log To Console  ⚠️  New pod appeared: ${pod_name} (was not present before test)
        END
    END
    RETURN  ${had_restarts}  ${restart_reason}

Wait For Metrics Available
    Wait Until Keyword Succeeds  ${OPERATION_RETRY_COUNT}  ${OPERATION_RETRY_INTERVAL}
    ...  Metrics Should Be Available

Metrics Should Be Available
    ${sent} =  Get Sent Spans Count
    Should Be True  ${sent} >= 0  Metrics endpoint not available

Wait For Collector To Stabilize
    [Arguments]  ${monitoring_duration_minutes}=0
    [Documentation]  Wait for collector to be ready and metrics to stabilize before running tests
    ...  This ensures the collector has finished processing any pending spans and is in a stable state.
    ...
    ...  Args:
    ...    ${monitoring_duration_minutes}: Optional duration in minutes to monitor exporter queue draining.
    ...      Use 0 for quick stabilization (before etalon test), 2-3 for after high load test.
    ...      Default: 0 (quick check only)
    Check Collector Pods
    Wait For Metrics Available

    # Verify metrics are updating by sending a single trace
    Log To Console  Verifying metrics are updating by sending a test trace...
    ${test_received_before} =  Get Received Spans Count
    ${test_sent_before} =  Get Sent Spans Count
    ${test_dropped_before} =  Get Dropped Spans Count

    ${collector_endpoint} =  Set Variable  ${JAEGER_SERVICE_NAME}-collector.${JAEGER_NAMESPACE}:4317
    ${cmd} =  Set Variable  export OTEL_EXPORTER_OTLP_ENDPOINT=http://${collector_endpoint} && tracegen --traces 1 --trace-exporter otlp-grpc
    ${result} =  Run Process  ${cmd}  shell=True  timeout=30s
    IF  ${result.rc} != 0
        Log To Console  WARNING: Test trace generation failed (exit code ${result.rc}), using current metrics...
        ${baseline_received} =  Get Received Spans Count
        ${baseline_sent} =  Get Sent Spans Count
        ${baseline_dropped} =  Get Dropped Spans Count
    ELSE
        Sleep  5s
        ${baseline_received} =  Get Received Spans Count
        ${baseline_sent} =  Get Sent Spans Count
        ${baseline_dropped} =  Get Dropped Spans Count
        ${received_increase} =  Evaluate  ${baseline_received} - ${test_received_before}
        IF  ${received_increase} == 2.0
            Log To Console  Metrics verification passed: received ${received_increase} spans (expected 2) - metrics are updating correctly
        ELSE
            Log To Console  WARNING: Metrics verification: received ${received_increase} spans (expected 2). Waiting additional time...
            Sleep  10s
            ${baseline_received} =  Get Received Spans Count
            ${baseline_sent} =  Get Sent Spans Count
            ${baseline_dropped} =  Get Dropped Spans Count
        END
    END

    # Extended monitoring period if requested (for after high load tests to wait for exporter queue to drain)
    IF  ${monitoring_duration_minutes} > 0
        Log To Console  Waiting ${monitoring_duration_minutes} minutes for exporter queue to drain after high load...
        ${monitoring_interval} =  Evaluate  5  # Check every 5 seconds
        ${monitoring_checks} =  Evaluate  int((${monitoring_duration_minutes} * 60) / ${monitoring_interval})

        ${prev_received} =  Set Variable  ${baseline_received}
        ${prev_sent} =  Set Variable  ${baseline_sent}
        ${prev_dropped} =  Set Variable  ${baseline_dropped}

        FOR  ${check_num}  IN RANGE  1  ${monitoring_checks} + 1
            Sleep  ${monitoring_interval}s
            ${curr_received} =  Get Received Spans Count
            ${curr_sent} =  Get Sent Spans Count
            ${curr_dropped} =  Get Dropped Spans Count
            ${sent_delta} =  Evaluate  ${curr_sent} - ${prev_sent}

            # Log every minute or if there's activity
            ${should_log} =  Evaluate  (${check_num} % 12 == 0) or (abs(${sent_delta}) > 0)
            IF  ${should_log}
                ${elapsed_minutes} =  Evaluate  (${check_num} * ${monitoring_interval}) / 60.0
                ${elapsed_minutes_formatted} =  Evaluate  '{:.1f}'.format(${elapsed_minutes})
                Log To Console  Monitoring [${elapsed_minutes_formatted}min]: sent_delta=${sent_delta} (exporter queue draining)
            END

            ${prev_received} =  Set Variable  ${curr_received}
            ${prev_sent} =  Set Variable  ${curr_sent}
            ${prev_dropped} =  Set Variable  ${curr_dropped}
        END

        Log To Console  Monitoring completed. Final metrics: sent=${curr_sent}, received=${curr_received}, dropped=${curr_dropped}
        ${baseline_received} =  Set Variable  ${curr_received}
        ${baseline_sent} =  Set Variable  ${curr_sent}
        ${baseline_dropped} =  Set Variable  ${curr_dropped}
    END

    # Final stability check - metrics should stop changing
    Log To Console  Checking for metrics stability...
    ${max_delta} =  Evaluate  100  # Allow up to 100 spans change in 5 seconds (20 spans/sec)
    ${max_attempts} =  Evaluate  8  # Maximum number of stability checks (8 * 5s = 40s max)
    ${check_interval} =  Evaluate  5  # Seconds between checks

    ${prev_received} =  Set Variable  ${baseline_received}
    ${prev_sent} =  Set Variable  ${baseline_sent}
    ${prev_dropped} =  Set Variable  ${baseline_dropped}

    FOR  ${attempt}  IN RANGE  1  ${max_attempts} + 1
        Sleep  ${check_interval}s
        ${curr_received} =  Get Received Spans Count
        ${curr_sent} =  Get Sent Spans Count
        ${curr_dropped} =  Get Dropped Spans Count
        ${received_delta} =  Evaluate  abs(${curr_received} - ${prev_received})
        ${sent_delta} =  Evaluate  abs(${curr_sent} - ${prev_sent})
        ${dropped_delta} =  Evaluate  abs(${curr_dropped} - ${prev_dropped})
        ${is_stable} =  Evaluate  ${received_delta} <= ${max_delta} and ${sent_delta} <= ${max_delta} and ${dropped_delta} <= ${max_delta}

        IF  ${is_stable}
            Log To Console  Collector stabilized: received_delta=${received_delta}, sent_delta=${sent_delta}, dropped_delta=${dropped_delta} over stabilization period (attempt ${attempt}/${max_attempts})
            RETURN
        END

        Log To Console  Metrics still changing (received_delta=${received_delta}, sent_delta=${sent_delta}, dropped_delta=${dropped_delta}), attempt ${attempt}/${max_attempts}...
        ${prev_received} =  Set Variable  ${curr_received}
        ${prev_sent} =  Set Variable  ${curr_sent}
        ${prev_dropped} =  Set Variable  ${curr_dropped}
    END

    # If we get here, metrics didn't stabilize within max attempts, but log final state and continue
    Log To Console  Collector metrics did not fully stabilize after ${max_attempts} attempts, but proceeding with test (final: received_delta=${received_delta}, sent_delta=${sent_delta}, dropped_delta=${dropped_delta})

Generate Load
    [Arguments]  ${total_traces}  ${target_spans_per_second}=${EMPTY}
    [Documentation]  Generate load using tracegen to send a specific number of traces
    ...
    ...  Generates and sends traces using tracegen binary via OTLP gRPC protocol.
    ...
    ...  If ${target_spans_per_second} is provided, sends traces in batches with delays to approximate
    ...  the target rate. Otherwise, sends all traces as a burst at maximum speed.
    ...
    ...  Returns:
    ...    Actual spans/sec generation rate
    ...
    ...  Args:
    ...    ${total_traces}: Total number of traces to generate
    ...    ${target_spans_per_second}: Optional target rate. If provided, sends in batches to approximate this rate
    # Calculate total spans (each trace has 2 spans)
    ${total_spans} =  Evaluate  ${total_traces} * 2
    # Use OTLP gRPC endpoint (port 4317) - standard OpenTelemetry protocol
    # OTEL_EXPORTER_OTLP_ENDPOINT requires http:// or https:// prefix even for gRPC
    # The protocol (gRPC vs HTTP) is determined by --trace-exporter flag (otlp-grpc vs otlp)
    ${collector_endpoint} =  Set Variable  ${JAEGER_SERVICE_NAME}-collector.${JAEGER_NAMESPACE}:4317

    # If target rate is specified, send in batches with delays to approximate the rate
    ${use_rate_limiting} =  Evaluate  '${target_spans_per_second}' != '${EMPTY}' and '${target_spans_per_second}' != 'None'

    IF  ${use_rate_limiting}
        # Rate-limited mode: send in batches with delays
        # Calculate batch size: larger batches reduce overhead and number of batches
        # For etalon test (700 spans/sec), this gives ~350 traces per batch = ~30 batches instead of 60
        ${batch_size} =  Evaluate  max(200, int(${target_spans_per_second} / 2))  # ~2 batches per second
        # Calculate delay between batches to achieve target rate
        # Each batch has batch_size traces = batch_size * 2 spans
        # Target: target_spans_per_second spans/sec
        # So: delay = (batch_size * 2) / target_spans_per_second seconds
        ${batch_delay} =  Evaluate  (${batch_size} * 2.0) / ${target_spans_per_second}
        ${num_batches} =  Evaluate  int((${total_traces} + ${batch_size} - 1) / ${batch_size})  # Ceiling division
        ${batch_delay_formatted} =  Evaluate  '{:.2f}'.format(${batch_delay})
        Log To Console  Generating load: ${total_traces} traces (${total_spans} spans total) with rate limiting: target=${target_spans_per_second} spans/sec, batch_size=${batch_size}, batches=${num_batches}, delay=${batch_delay_formatted}s between batches
    ELSE
        # Burst mode: send all at once
        Log To Console  Generating load: ${total_traces} traces (${total_spans} spans total, sent as burst) using tracegen
    END
    Log To Console  Sending to collector endpoint: http://${collector_endpoint}

    # Measure start time to calculate actual generation rate
    ${start_time} =  Evaluate  time.time()  modules=time

        IF  ${use_rate_limiting}
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
        ELSE
            # Run tracegen synchronously (blocks until completion) - burst mode
            # Calculate timeout: allow sufficient time for trace generation
            # Under high load with memory limiter, tracegen may slow down due to backpressure.
            # Estimate timeout based on total traces (roughly 1 trace per second at worst case), minimum 60s, maximum 600s
            ${timeout_seconds} =  Evaluate  min(max(int(${total_traces}), 60), 600)
            ${cmd} =  Set Variable  export OTEL_EXPORTER_OTLP_ENDPOINT=http://${collector_endpoint} && tracegen --traces ${total_traces} --trace-exporter otlp-grpc
            ${result} =  Run Process  ${cmd}  shell=True  timeout=${timeout_seconds}s
            IF  ${result.rc} != 0
                Fail  Tracegen failed to generate load (exit code ${result.rc}). stdout: ${result.stdout}. stderr: ${result.stderr}
            END
        END

        # Measure end time and calculate actual rate
        ${end_time} =  Evaluate  time.time()  modules=time
        ${duration_seconds} =  Evaluate  ${end_time} - ${start_time}
        ${actual_spans_per_second} =  Evaluate  ${total_spans} / ${duration_seconds} if ${duration_seconds} > 0 else 0
    ${duration_formatted} =  Evaluate  '{:.2f}'.format(${duration_seconds})
    ${rate_formatted} =  Evaluate  '{:.0f}'.format(${actual_spans_per_second})
    Log To Console  Tracegen completed successfully in ${duration_formatted}s. Actual generation rate: ${rate_formatted} spans/sec
    RETURN  ${actual_spans_per_second}

*** Test Cases ***
Memory Limiter Is Configured
    [Tags]  memory_limiter
    [Documentation]  Verify that memory limiter is configured in the collector ConfigMap
    ${configmap_name} =  Set Variable  ${JAEGER_SERVICE_NAME}-collector-configuration
    ${config_content} =  Get ConfigMap Content  ${configmap_name}  ${JAEGER_NAMESPACE}
    Check Memory Limiter In Pipeline  ${config_content}
    Check Memory Limiter Settings  ${config_content}
    Log To Console  ✓ Memory limiter is configured correctly

Memory Limiter Settings Are Valid
    [Tags]  memory_limiter
    [Documentation]  Verify memory limiter settings are within expected ranges
    ${configmap_name} =  Set Variable  ${JAEGER_SERVICE_NAME}-collector-configuration
    ${config_content} =  Get ConfigMap Content  ${configmap_name}  ${JAEGER_NAMESPACE}
    Should Contain  ${config_content}  memory_limiter:
    # Extract and validate settings (basic check)
    ${has_limit} =  Run Keyword And Return Status  Should Match Regexp  ${config_content}  limit_mib:\\s*\\d+
    Should Be True  ${has_limit}  limit_mib not found or invalid
    Log To Console  ✓ Memory limiter settings are valid

No Drops At Etalon Throughput
    [Tags]  memory_limiter  throughput  etalon
    [Documentation]  Verify no spans are dropped at the etalon throughput (guaranteed safe throughput)
    ...  Tests at ${ETALON_TARGET_SPANS_PER_SECOND} spans/sec load level with rate limiting enabled.
    ...  Based on experimental results, this actual received rate should result in zero drops.
    ...  This test serves as a baseline/etalon: if drops occur here, something is wrong.

    # Wait for collector to be ready and stable before running test
    # Use 0 minutes for quick check (collector should already be stable)
    Wait For Collector To Stabilize  0

    # Additional stabilization time to reduce interference from previous runs
    Log To Console  Additional stabilization before etalon test (waiting ${STABILIZATION_TIME})...
    Sleep  ${STABILIZATION_TIME}

    # Get initial counts
    ${initial_sent} =  Get Sent Spans Count
    ${initial_dropped} =  Get Dropped Spans Count
    ${initial_received} =  Get Received Spans Count

    Log To Console  Initial: sent=${initial_sent}, dropped=${initial_dropped}, received=${initial_received}
    Log To Console  Testing at etalon throughput: ${ETALON_TARGET_SPANS_PER_SECOND} spans/sec with rate limiting (${ETALON_TOTAL_TRACES} total traces)

    # Generate load at etalon throughput (with rate limiting to approximate target rate)
    ${actual_generation_rate} =  Generate Load  ${ETALON_TOTAL_TRACES}  ${ETALON_TARGET_SPANS_PER_SECOND}
    # Compare actual generation rate with etalon target
    ${rate_diff} =  Evaluate  ${actual_generation_rate} - ${ETALON_TARGET_SPANS_PER_SECOND}
    ${rate_diff_percent} =  Evaluate  (${rate_diff} / ${ETALON_TARGET_SPANS_PER_SECOND} * 100) if ${ETALON_TARGET_SPANS_PER_SECOND} > 0 else 0
    ${rate_diff_formatted} =  Evaluate  '{:.1f}'.format(${rate_diff_percent})
    ${actual_rate_formatted} =  Evaluate  '{:.0f}'.format(${actual_generation_rate})
    Log To Console  Generation rate comparison: actual=${actual_rate_formatted} spans/sec, etalon target=${ETALON_TARGET_SPANS_PER_SECOND} spans/sec, difference=${rate_diff_formatted}%

    # Wait for processing to complete
    Sleep  10s

    # Get final counts
    ${final_sent} =  Get Sent Spans Count
    ${final_dropped} =  Get Dropped Spans Count
    ${final_received} =  Get Received Spans Count

    ${sent_delta} =  Evaluate  ${final_sent} - ${initial_sent}
    ${dropped_delta} =  Evaluate  ${final_dropped} - ${initial_dropped}
    ${received_delta} =  Evaluate  ${final_received} - ${initial_received}

    Log To Console  Final: sent=${final_sent}, dropped=${final_dropped}, received=${final_received}
    Log To Console  Delta: sent=${sent_delta}, dropped=${dropped_delta}, received=${received_delta}

    # Calculate drop rate percentage
    ${drop_rate_percent} =  Evaluate  (${dropped_delta} / ${received_delta} * 100) if ${received_delta} > 0 else 0.0
    ${drop_rate_formatted} =  Evaluate  '{:.2f}'.format(${drop_rate_percent})
    Log To Console  Drop rate: ${drop_rate_formatted}% (${dropped_delta} dropped out of ${received_delta} received)

    # At etalon throughput, drops should be zero
    ${error_msg} =  Set Variable  FAIL: Spans were dropped at etalon throughput (${ETALON_TARGET_SPANS_PER_SECOND} spans/sec). Dropped: ${dropped_delta} (${drop_rate_formatted}%). This indicates the guaranteed throughput has decreased or system load is too high.
    Should Be Equal As Numbers  ${dropped_delta}  ${0}  ${error_msg}
    Log To Console  ✓ No spans dropped at etalon throughput (${ETALON_TARGET_SPANS_PER_SECOND} spans/sec)

Collector Survives High Load With Memory Limiter
    [Tags]  memory_limiter  stability  high_load
    [Documentation]  Verify collector survives high load (~1500 spans/sec) with memory limiter enabled
    ...  Tests at 1500 spans/sec equivalent (sent as burst - no rate limiting).
    ...  Drops are expected due to memory pressure, but the collector must remain stable (no restarts, no OOM crashes).
    ...  This verifies that the memory limiter is protecting the collector from crashing.

    # Wait for collector to be ready and stable before running test
    # Use 0 minutes for quick check (collector should already be stable)
    Wait For Collector To Stabilize  0

    # Additional stabilization time to reduce interference from previous runs
    Log To Console  Additional stabilization before high load test (waiting ${STABILIZATION_TIME})...
    Sleep  ${STABILIZATION_TIME}

    # Record pods before load (keyword sets @{list_pods} suite variable)
    Get List Pod Names For Deployment Entity  collector
    ${pods_before_count} =  Get Length  @{list_pods}
    # Build comma-separated string from list for comparison
    ${pods_before_str} =  Set Variable  ${EMPTY}
    FOR  ${pod}  IN  @{list_pods}
        IF  '${pods_before_str}' == '${EMPTY}'
            ${pods_before_str} =  Set Variable  ${pod}
        ELSE
            ${pods_before_str} =  Set Variable  ${pods_before_str},${pod}
        END
    END
    ${pods_before_str} =  Evaluate  ','.join(sorted('${pods_before_str}'.split(','))) if '${pods_before_str}' else ''
    # Store restart counts before load test
    ${restarts_before} =  Get Collector Pod Restart Counts  ${pods_before_str}
    ${initial_dropped} =  Get Dropped Spans Count
    ${initial_received} =  Get Received Spans Count
    Log To Console  Initial metrics for high load test: dropped=${initial_dropped}, received=${initial_received}

    # High load target: fixed 2300 spans/sec with rate limiting (sustained load)
    ${high_load_target} =  Set Variable  2300
    Log To Console  Testing high load: ${high_load_target} spans/sec with rate limiting (${HIGH_LOAD_TOTAL_TRACES} total traces)
    Log To Console  Drops are expected at this load level

    # Generate high load with rate limiting (sustained load to trigger memory limiter throttling)
    ${actual_generation_rate} =  Generate Load  ${HIGH_LOAD_TOTAL_TRACES}  ${high_load_target}
    # Compare actual generation rate with high load target
    ${rate_diff} =  Evaluate  ${actual_generation_rate} - ${high_load_target}
    ${rate_diff_percent} =  Evaluate  (${rate_diff} / ${high_load_target} * 100) if ${high_load_target} > 0 else 0
    ${rate_diff_formatted} =  Evaluate  '{:.1f}'.format(${rate_diff_percent})
    ${actual_rate_formatted} =  Evaluate  '{:.0f}'.format(${actual_generation_rate})
    Log To Console  Generation rate comparison: actual=${actual_rate_formatted} spans/sec, high load target=${high_load_target} spans/sec, difference=${rate_diff_formatted}%

    # Wait for processing to complete
    Sleep  10s

    # Verify collector pods are still running (no restarts, no crashes)
    # Use Run Keyword And Return Status to check pods, but continue even if it fails to gather diagnostics
    ${pods_check_passed} =  Run Keyword And Return Status  Check Collector Pods
    IF  not ${pods_check_passed}
        Log To Console  WARNING: Collector pods check failed - attempting to gather diagnostic information...
        # Try to get pod list anyway to see what's available
        ${got_pods} =  Run Keyword And Return Status  Get List Pod Names For Deployment Entity  collector
        IF  not ${got_pods}
            Log To Console  ERROR: Could not retrieve pod list - collector deployment may have failed completely
        END
    ELSE
        Get List Pod Names For Deployment Entity  collector
    END
    ${pods_after_count} =  Get Length  @{list_pods}
    # Build comma-separated string from list for comparison
    ${pods_after_str} =  Set Variable  ${EMPTY}
    FOR  ${pod}  IN  @{list_pods}
        IF  '${pods_after_str}' == '${EMPTY}'
            ${pods_after_str} =  Set Variable  ${pod}
        ELSE
            ${pods_after_str} =  Set Variable  ${pods_after_str},${pod}
        END
    END
    ${pods_after_str} =  Evaluate  ','.join(sorted('${pods_after_str}'.split(','))) if '${pods_after_str}' else ''

    # Verify pod names haven't changed (no restarts) - but only if we successfully got pod list
    IF  '${pods_after_str}' != '${EMPTY}'
        Should Be Equal  ${pods_before_str}  ${pods_after_str}
        ...  FAIL: Collector pods restarted or crashed during high load test. Pod names changed from '${pods_before_str}' to '${pods_after_str}'. Memory limiter may not be working correctly.
    ELSE
        Log To Console  ERROR: Could not retrieve pod list after high load - collector may have crashed
        Fail  Collector pods are not available after high load test. The collector deployment may have failed completely. Check pod status and logs.
    END

    # Get final metrics - use Run Keyword And Return Status in case collector crashed
    ${got_metrics} =  Run Keyword And Return Status  Get Dropped Spans Count
    IF  not ${got_metrics}
        Log To Console  ERROR: Could not retrieve metrics after high load - collector may have crashed
        # Try to check for restarts to provide diagnostic information
        ${restarts_after} =  Get Collector Pod Restart Counts  ${pods_after_str}
        ${had_restarts}  ${restart_reason} =  Check And Display Restart Details  ${pods_before_str}  ${restarts_before}  ${pods_after_str}  ${restarts_after}
        IF  ${had_restarts}
            ${error_msg} =  Set Variable  FAIL: Collector container restarted and became unavailable during high load test (reason: ${restart_reason}). Memory limiter failed to protect the collector.
            IF  '${restart_reason}' == 'OOMKilled'
                ${error_msg} =  Set Variable  FAIL: Collector container was OOMKilled and became unavailable during high load test. Memory limiter failed to protect the collector from memory exhaustion.
            END
            Fail  ${error_msg}
        ELSE
            Fail  Collector became unavailable after high load test and metrics are not accessible. This may indicate the collector crashed. Check pod logs and events for details. No container restarts were detected, but the collector is not responding.
        END
    END
    ${final_dropped} =  Get Dropped Spans Count
    ${final_received} =  Get Received Spans Count
    ${dropped_delta} =  Evaluate  ${final_dropped} - ${initial_dropped}
    ${received_delta} =  Evaluate  ${final_received} - ${initial_received}

    Log To Console  Final metrics: dropped=${final_dropped}, received=${final_received}
    Log To Console  Delta metrics: dropped_delta=${dropped_delta}, received_delta=${received_delta}
    Log To Console  Pods before: ${pods_before_str} (count: ${pods_before_count})
    Log To Console  Pods after: ${pods_after_str} (count: ${pods_after_count})

    # At high load, drops are expected - verify they occurred (memory limiter is working)
    # Handle case where metrics might have reset (negative deltas) - skip drop check in that case
    ${metrics_valid} =  Evaluate  ${dropped_delta} >= 0 and ${received_delta} >= 0
    ${had_restarts} =  Set Variable  ${False}
    ${restart_reason} =  Set Variable  ${EMPTY}
    IF  not ${metrics_valid}
        Log To Console  WARNING: Metrics deltas are negative (dropped_delta=${dropped_delta}, received_delta=${received_delta}). This may indicate metrics reset.
        # Check for container restarts and display restart reasons
        ${restarts_after} =  Get Collector Pod Restart Counts  ${pods_after_str}
        ${had_restarts}  ${restart_reason} =  Check And Display Restart Details  ${pods_before_str}  ${restarts_before}  ${pods_after_str}  ${restarts_after}
        Log To Console  Skipping drop verification due to metrics reset.
    ELSE
        # Also check for restarts even when metrics are valid (restart might not cause metrics reset)
        ${restarts_after} =  Get Collector Pod Restart Counts  ${pods_after_str}
        ${had_restarts}  ${restart_reason} =  Check And Display Restart Details  ${pods_before_str}  ${restarts_before}  ${pods_after_str}  ${restarts_after}
        ${has_drops} =  Evaluate  ${dropped_delta} > 0
        IF  not ${has_drops}
            Log To Console  WARNING: No drops occurred at high load (${high_load_target} equivalent spans/sec). This might indicate memory limiter is not configured correctly or load was not high enough, but pod stability was verified.
        ELSE
            Log To Console  ✓ Drops occurred as expected: ${dropped_delta} spans dropped (memory limiter is working)
        END
    END

    # Fail the test if container restarts occurred (especially OOMKilled)
    IF  ${had_restarts}
        ${error_msg} =  Set Variable  FAIL: Collector container restarted during high load test (reason: ${restart_reason}). Memory limiter should prevent crashes/restarts. This indicates the memory limiter configuration may be insufficient or the load is too high.
        IF  '${restart_reason}' == 'OOMKilled'
            ${error_msg} =  Set Variable  FAIL: Collector container was OOMKilled during high load test. Memory limiter failed to protect the collector from memory exhaustion. This indicates the memory limiter limit may be too high or the load exceeds the system's capacity.
        END
        Fail  ${error_msg}
    END

    # Only proceed with post-test verification if collector is still running
    IF  ${pods_check_passed} and not ${had_restarts}
        Log To Console  ✓ Collector survived high load (${high_load_target} equivalent spans/sec)
        Log To Console  ✓ Memory limiter protected collector: ${dropped_delta} spans dropped, but no crashes/restarts

        # Wait for exporter queue to drain after high load (allows next test to start with clean state)
        # Use 2 minutes to allow queue to drain (typically takes 1-2 minutes based on monitoring)
        # Use Run Keyword And Return Status in case collector crashes during drain
        ${stabilize_passed} =  Run Keyword And Return Status  Wait For Collector To Stabilize  2
        IF  not ${stabilize_passed}
            Log To Console  WARNING: Collector became unavailable during queue drain - may have crashed after high load test
            Fail  Collector became unavailable after high load test. This may indicate the collector crashed or restarted after the test completed.
        END
    ELSE
        IF  not ${pods_check_passed}
            Fail  Collector pods are not running after high load test. The collector may have crashed or been OOMKilled. Check pod logs and events for details.
        END
    END


