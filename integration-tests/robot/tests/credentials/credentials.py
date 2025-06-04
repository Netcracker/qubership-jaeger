import yaml, base64

def replace_basic_auth_structured(secret):
    if not hasattr(secret, 'data') or 'config.yaml' not in secret.data:
        raise ValueError("Secret doesnt contain config.yaml in data")
    raw_yaml = base64.b64decode(secret.data['config.yaml']).decode()
    parsed = yaml.safe_load(raw_yaml)
    def rec(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k == 'credentials' and isinstance(v, list):
                    o[k] = ["Basic " + base64.b64encode(b"test1:test1").decode()]
                else:
                    rec(v)
        elif isinstance(o, list):
            for i in o:
                rec(i)
    rec(parsed)
    updated_yaml = base64.b64encode(yaml.dump(parsed, default_flow_style=False, sort_keys=False, allow_unicode=True).encode()).decode()
    secret.data['config.yaml'] = updated_yaml
    return secret