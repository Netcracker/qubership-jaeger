import base64
import yaml

def replace_basic_auth_structured(yaml_text: str) -> str:
    def update(data, new_encoded):
        if isinstance(data, dict):
            return {k: update(v, new_encoded) for k, v in data.items()}
        if isinstance(data, list):
            return [update(i, new_encoded) for i in data]
        if isinstance(data, str) and data.strip().startswith("Basic "):
            return f"Basic {new_encoded}"
        return data

    encoded = base64.b64encode(b"test1:test1").decode()
    parsed = yaml.safe_load(yaml_text)
    parsed.pop("metadata", None)
    updated = update(parsed, encoded)
    return updated