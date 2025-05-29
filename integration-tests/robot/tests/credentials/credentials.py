import base64
import yaml

class Credentials:
    @keyword("Replace Basic Auth Structured")
    def replace_basic_auth_structured(self, secret: dict) -> dict:
        """
        Принимает Kubernetes Secret (dict), заменяет Basic Auth строки в config.yaml,
        возвращает обновлённый dict.
        """
        b64_config = secret['data']['config.yaml']
        yaml_string = base64.b64decode(b64_config).decode('utf-8')

        new_basic = "Basic " + base64.b64encode(b"test1:test1").decode()
        modified_yaml_string = "\n".join([
            new_basic if line.strip().startswith("Basic ") else line
            for line in yaml_string.splitlines()
        ])

        new_b64_config = base64.b64encode(modified_yaml_string.encode()).decode('utf-8')

        updated = dict(secret)
        updated['data'] = dict(secret['data'])
        updated['data']['config.yaml'] = new_b64_config
        return updated