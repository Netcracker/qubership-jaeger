import base64
import yaml
from copy import deepcopy

def replace_basic_auth_structured(secret):
    print("[INFO] Получаем config.yaml из секрета и декодируем base64...")

    # Получаем base64 строку из secret.data (атрибут объекта)
    encoded = secret.data['config.yaml']
    yaml_string = base64.b64decode(encoded).decode('utf-8')

    print("[INFO] YAML-документ после декодирования:")
    print(yaml_string)

    data = yaml.safe_load(yaml_string)

    print("[INFO] Заменяем значение Basic авторизации...")
    new_auth = "Basic " + base64.b64encode(b"test1:test1").decode()
    replaced = False

    for item in data.get('auths', []):
        if isinstance(item, dict) and 'value' in item:
            if item['value'].startswith("Basic "):
                print(f"[DEBUG] Было значение: {item['value']}")
                item['value'] = new_auth
                print(f"[DEBUG] Стало значение: {item['value']}")
                replaced = True

    if not replaced:
        print("[WARN] Ничего не заменено: ключ 'auths' отсутствует или нет подходящих значений.")

    print("[INFO] Собираем YAML обратно и кодируем в base64...")
    new_yaml = yaml.safe_dump(data)
    updated_encoded = base64.b64encode(new_yaml.encode()).decode()

    print("[INFO] YAML после изменений:")
    print(new_yaml)

    print("[INFO] Возвращаем обновлённый секрет.")
    # Копируем исходный объект, чтобы не менять оригинал
    new_secret = deepcopy(secret)
    new_secret.data = dict(secret.data)  # копия словаря data
    new_secret.data['config.yaml'] = updated_encoded
    return new_secret