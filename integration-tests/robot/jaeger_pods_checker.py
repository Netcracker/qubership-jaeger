import logging
import os
import time

from PlatformLibrary import PlatformLibrary

environ = os.environ
namespace = environ.get("JAEGER_NAMESPACE")
service = environ.get("JAEGER_SERVICE_NAME")

query = f"{service}-query"
collector = f"{service}-collector"

timeout = 300

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="[%(asctime)s][%(levelname)s] %(message)s")

    logging.info("Start Jaeger pods checker script")
    logging.info(f"Parameters to run: namespace={namespace}, timeout={timeout}")
    try:
        k8s_lib = PlatformLibrary("true")
    except Exception as e:
        logging.error("Failed to initialize PlatformLibrary", e.message, e.traceback)
        exit(1)

    logging.info("Check deployments readiness")
    start_time = time.time()
    attempts = 0
    while time.time() < start_time + timeout:
        try:
            query_deployments = k8s_lib.get_deployment_entities_count_for_service(namespace, query, "name")
            query_ready_deployments = k8s_lib.get_active_deployment_entities_count_for_service(namespace, query, "name")

            collector_deployments = k8s_lib.get_deployment_entities_count_for_service(namespace, collector, "name")
            collector_ready_deployments = k8s_lib.get_active_deployment_entities_count_for_service(
                namespace, collector, "name"
            )

            logging.info(
                f"{query}: total = {query_deployments}, ready = {query_ready_deployments}, "
                f"{collector}: total = {collector_deployments}, ready = {collector_ready_deployments}"
            )
        except Exception as e:
            logging.error(f"Failed to get deployment entities count for service: {e}")
            continue

        if (query_deployments == query_ready_deployments and query_deployments != 0) and (
            collector_deployments == collector_ready_deployments and collector_deployments != 0
        ):
            logging.info("Jaeger query and collector deployments are ready")
            time.sleep(5)
            exit(0)

        logging.info(
            f"Number of attempts = {attempts}, remaining time = {round((start_time + timeout) - time.time())} seconds"
        )
        attempts += 1
        time.sleep(10)

    logging.error(f"Jaeger query and collector deployments are not ready for at least {timeout} seconds")
    exit(1)
