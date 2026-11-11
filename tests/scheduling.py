"""Bounded fixture scheduling with stable shards and measured longest-first work."""

import hashlib
import json
import math
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def arguments(parser, default_jobs=1):
    parser.add_argument("-j", "--jobs", type=int, default=default_jobs)
    parser.add_argument("--shard-index", type=int, default=0)
    parser.add_argument("--shard-count", type=int, default=1)


def select(items, key, index=0, count=1):
    if count < 1 or not 0 <= index < count:
        raise ValueError("shard index must be in [0, shard count)")
    return [item for item in items
            if int.from_bytes(hashlib.sha256(key(item).encode()).digest()[:8], "big") % count
            == index]


def run(items, execute, directory, jobs, key, initial=None):
    if jobs < 1:
        raise ValueError("jobs must be positive")
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "durations.json"
    try:
        previous = json.loads(path.read_text())
    except (OSError, ValueError):
        previous = initial or {}
    if not isinstance(previous, dict):
        previous = {}
    durations = {name: value for name, value in previous.items()
                 if isinstance(value, (int, float)) and math.isfinite(value) and value >= 0}
    ordered = sorted(items, key=lambda item: (-durations.get(key(item), 0), key(item)))

    def timed(item):
        begin = time.perf_counter()
        try:
            result, error = execute(item), None
        except Exception as failure:
            result, error = None, str(failure) or type(failure).__name__
        return item, result, error, time.perf_counter() - begin

    with ThreadPoolExecutor(max_workers=jobs) as pool:
        results = list(pool.map(timed, ordered))
    for item, _, _, elapsed in results:
        durations[key(item)] = elapsed
    path.write_text(json.dumps(dict(sorted(durations.items())), indent=2) + "\n")
    return sorted(results, key=lambda result: key(result[0]))
