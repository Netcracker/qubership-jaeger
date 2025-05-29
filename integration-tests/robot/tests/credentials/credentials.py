import yaml, base64

def replace_basic_auth_structured(secret):
    print(">>> Начало обработки секрета")

    # Преобразование V1Secret в обычный dict (если надо)
    if not isinstance(secret, dict):
        print(">>> Преобразуем объект V1Secret в dict")
        secret = ApiClient().sanitize_for_serialization(secret)

    print(f"Исходные ключи: {list(secret.keys())}")

    for k in ['kind', 'apiVersion', 'metadata']: 
        if k in secret: 
            print(f"Удаление ключа: {k}")
            secret.pop(k)

    raw_b64 = secret['data']['config.yaml']
    print(">>> Декодирование config.yaml из base64")
    raw_yaml = base64.b64decode(raw_b64).decode()
    s = yaml.safe_load(raw_yaml)
    print(">>> YAML успешно разобран")

    def rec(o): 
        if isinstance(o, dict): 
            for k, v in o.items(): 
                if k == 'credentials' and isinstance(v, list): 
                    print(f"Патчим credentials: было {v}")
                    o[k] = ["Basic " + base64.b64encode(b"test1:test1").decode()]
                    print(f"Стало: {o[k]}")
                else: 
                    rec(v)
        elif isinstance(o, list): 
            for i in o: rec(i)

    print(">>> Поиск и замена credentials")
    rec(s)

    print(">>> Обратное кодирование YAML в base64")
    encoded_yaml = base64.b64encode(yaml.dump(s).encode()).decode()
    secret['data']['config.yaml'] = encoded_yaml
    print(">>> Готово, возвращаю патч")

    return secret