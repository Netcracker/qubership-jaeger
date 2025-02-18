import json
import random
from datetime import datetime, timezone


def generate_trace():
    with open('./tests/libs/resources/spans.json') as f:
        data = json.load(f)

    timestamp = _generate_timestamp()

    parent_id = _generate_id(16)

    fs = data[0]
    fs['traceId'] = parent_id
    fs['id'] = parent_id
    fs['timestamp'] = timestamp
    fs['annotations'][0]['timestamp'] = timestamp
    fs['annotations'][1]['timestamp'] = timestamp + 14861
    return data


def _generate_timestamp():
    timestamp = int(datetime.now(timezone.utc).timestamp() * 1_000_000)
    return timestamp if timestamp % 10 != 0 else timestamp - 1


def _generate_id(n):
    return ''.join(random.choices('0123456789abcdef', k=n))
