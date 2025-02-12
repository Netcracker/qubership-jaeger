import datetime
import json
import random
from datetime import timezone


def generate_trace():
    with open('./tests/libs/resources/spans.json') as f:
        data = json.load(f)

    dt = datetime.datetime.now(timezone.utc)

    utc_time = dt.replace(tzinfo=timezone.utc)
    timestamp = utc_time.timestamp()
    parent_id = _generate_id(16)

    fs = data[0]
    fs['traceId'] = parent_id
    fs['id'] = parent_id
    fs['timestamp'] = _format_tmstmp(timestamp)
    fs['annotations'][0]['timestamp'] = _format_tmstmp(timestamp)
    fs['annotations'][1]['timestamp'] = _format_tmstmp(timestamp + 0.014861)

    return data


def _format_tmstmp(timestamp, ch_count=17):
    return int(''.join(str(timestamp).split('.'))[:ch_count])


def _generate_id(n):
    return ''.join(random.choices('0123456789abcdef', k=n))
