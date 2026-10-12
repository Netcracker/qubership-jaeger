"""Decode Jaeger collector/query runtime config from Kubernetes Secret (config.yaml key)."""

import base64


def config_yaml_from_secret(secret):
    """Return UTF-8 config.yaml body. API returns Secret.data values base64-encoded."""
    data = getattr(secret, "data", None) or {}
    raw = data.get("config.yaml")
    if raw is None:
        raise ValueError("runtime secret has no config.yaml key")
    if isinstance(raw, bytes):
        return base64.b64decode(raw).decode("utf-8")
    return base64.b64decode(raw).decode("utf-8")
