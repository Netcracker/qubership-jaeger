"""Helper functions for accessing Kubernetes pod status in Robot Framework tests."""

from typing import Dict, List, Optional

try:
    from kubernetes import client

    KUBERNETES_AVAILABLE = True
except ImportError:
    KUBERNETES_AVAILABLE = False

from PlatformLibrary import get_kubernetes_api_client


def _get_k8s_client():
    """Initialize and return Kubernetes API client (CoreV1Api) via platform get_kubernetes_api_client."""
    if not KUBERNETES_AVAILABLE:
        return None
    api_client = get_kubernetes_api_client()
    return client.CoreV1Api(api_client)


def get_pod_container_restart_count(pod_name: str, container_name: str, namespace: str) -> int:
    """
    Get restart count for a specific container in a pod.

    Args:
        pod_name: Name of the pod
        container_name: Name of the container
        namespace: Kubernetes namespace

    Returns:
        int: Restart count, or 0 if unable to retrieve
    """
    if not KUBERNETES_AVAILABLE:
        return 0

    k8s_client = _get_k8s_client()
    if not k8s_client:
        return 0

    try:
        pod = k8s_client.read_namespaced_pod(pod_name, namespace)
        for container_status in pod.status.container_statuses or []:
            if container_status.name == container_name:
                return container_status.restart_count or 0
    except Exception:
        # Return 0 on any error (pod not found, API error, etc.)
        return 0

    return 0


def get_pod_container_termination_details(pod_name: str, container_name: str, namespace: str) -> Optional[Dict]:
    """
    Get termination details for a container's last termination.

    Args:
        pod_name: Name of the pod
        container_name: Name of the container
        namespace: Kubernetes namespace

    Returns:
        dict: Dictionary with 'reason', 'exitCode', 'message', 'finishedAt', or None if no termination
    """
    if not KUBERNETES_AVAILABLE:
        return None

    k8s_client = _get_k8s_client()
    if not k8s_client:
        return None

    try:
        pod = k8s_client.read_namespaced_pod(pod_name, namespace)
        for container_status in pod.status.container_statuses or []:
            if container_status.name == container_name:
                if container_status.last_state and container_status.last_state.terminated:
                    terminated = container_status.last_state.terminated
                    return {
                        "reason": terminated.reason or "Unknown",
                        "exitCode": terminated.exit_code if terminated.exit_code is not None else "N/A",
                        "message": terminated.message or "",
                        "finishedAt": terminated.finished_at.isoformat() if terminated.finished_at else "N/A",
                    }
    except Exception:
        # Return None on any error
        return None

    return None


def get_pod_events(pod_name: str, namespace: str, limit: int = 20) -> List[str]:
    """
    Get recent events for a pod.

    Args:
        pod_name: Name of the pod
        namespace: Kubernetes namespace
        limit: Maximum number of events to return

    Returns:
        list: List of event strings in format "LASTSEEN REASON MESSAGE"
    """
    if not KUBERNETES_AVAILABLE:
        return []

    k8s_client = _get_k8s_client()
    if not k8s_client:
        return []

    try:
        events = k8s_client.list_namespaced_event(namespace=namespace, field_selector=f"involvedObject.name={pod_name}")
        # Sort by last timestamp (most recent first)
        sorted_events = sorted(
            events.items, key=lambda e: e.last_timestamp.timestamp() if e.last_timestamp else 0, reverse=True
        )
        result = []
        for event in sorted_events[:limit]:
            last_seen = event.last_timestamp.isoformat() if event.last_timestamp else "N/A"
            reason = event.reason or "N/A"
            message = event.message or "N/A"
            result.append(f"{last_seen} {reason} {message}")
        return result
    except Exception:
        # Return empty list on any error
        return []
