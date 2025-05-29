import yaml, base64

def replace_basic_auth_structured(secret):
    print(">>> Начало обработки секрета")

    # Обрабатываем .data — должно быть в secret уже
    if not hasattr(secret, 'data') or 'config.yaml' not in secret.data:
        raise ValueError("Секрет не содержит config.yaml в data")

    print(">>> Декодируем config.yaml из base64")
    raw_yaml = base64.b64decode(secret.data['config.yaml']).decode()

    print(">>> Парсим YAML")
    parsed = yaml.safe_load(raw_yaml)

    def rec(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k == 'credentials' and isinstance(v, list):
                    print(f">>> Найдены credentials: {v}, заменяю...")
                    o[k] = ["Basic " + base64.b64encode(b"test1:test1").decode()]
                    print(f">>> Заменено на: {o[k]}")
                else:
                    rec(v)
        elif isinstance(o, list):
            for i in o:
                rec(i)

    print(">>> Поиск и замена credentials")
    rec(parsed)

    print(">>> Кодируем YAML обратно в base64")
    updated_yaml = base64.b64encode(yaml.dump(parsed, default_flow_style=False, sort_keys=False, allow_unicode=True).encode()).decode()

    # Обновляем секрет
    secret.data['config.yaml'] = updated_yaml
    print(">>> Готово, возвращаю обновлённый секрет")

    return secret