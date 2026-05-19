# Utils Organization

`utils/` holds pure Python helpers used across assets, schedules, sensors. Framework-free; if a function imports Dagster, it doesn't belong here.

## What lives in utils

- Date conversion / formatting (`convert_date`, `to_iso_utc`, `last_n_days`)
- File save patterns (`save_data` with consistent output paths and naming)
- S3 / object-store helpers that are not full clients (path builders, naming conventions)
- Generic data shape helpers (chunking, batching, deduplication)
- Cron / time math (next-business-day, schedule offset calculators)
- Parsing helpers (xmltodict wrappers, JSON normalizers)

## What does NOT live in utils

- API clients — those are Resources (`resources/<system>_resource.py`)
- Dagster decorators (`@asset`, `@op`, `@resource`, `@sensor`, `@schedule`)
- Anything that depends on environment / deployment context (read env in Resources, pass in)
- Source-specific business logic (one source's quirks → that source's asset folder)

## Splitting by concern

A monolithic `utils.py` accumulates unrelated functions and becomes unreadable. Split by concern:

```
utils/
├── __init__.py
├── s3_utils.py          # S3 path builders, date-based file naming, upload helpers
├── date_utils.py        # convert_date, last_n_days, business-day math
├── pandas_utils.py      # DataFrame chunking, dedup, common transforms
└── utils.py             # truly generic — save_data, retry decorators, logging helpers
```

When a category grows past ~10 functions or ~300 lines, split again.

## Re-exports via `__init__.py`

Optional. Helps if a few functions are used everywhere:

```python
# utils/__init__.py
from .s3_utils import convert_date
from .utils import save_data
```

Then assets can `from ...utils import s3_utils, utils` or `from ...utils import convert_date, save_data`.

Don't re-export everything — flat namespaces lose the by-concern organization.

## Patterns to follow

### Helper with timezone-aware defaults

```python
# utils/date_utils.py
from datetime import datetime, timezone, timedelta

def convert_date(date_input, fmt="%Y-%m-%d"):
    """Convert a date input (str or datetime) to a formatted string. UTC by default."""
    if isinstance(date_input, str):
        date_input = datetime.fromisoformat(date_input)
    if date_input.tzinfo is None:
        date_input = date_input.replace(tzinfo=timezone.utc)
    return date_input.strftime(fmt)


def last_n_days(n: int) -> list[str]:
    """Return a list of YYYY-MM-DD strings for the last n days, ending yesterday."""
    today = datetime.now(timezone.utc).date()
    return [(today - timedelta(days=i)).isoformat() for i in range(1, n + 1)]
```

### File save helper

```python
# utils/utils.py
import os, json
from datetime import datetime

def save_data(result_final, date, output_dir, type="daily", **kwargs):
    """Save records to a date-stamped JSONL file under output_dir. Returns list of paths."""
    os.makedirs(output_dir, exist_ok=True)
    date_str = datetime.fromisoformat(date.replace("Z", "+00:00")).strftime("%Y%m%d")
    filename = f"{type}_{date_str}.jsonl"
    path = os.path.join(output_dir, filename)
    with open(path, "w") as f:
        for record in result_final:
            f.write(json.dumps(record) + "\n")
    return [path]
```

Pattern points:
- Returns a list even for one file — uniform return shape across helpers
- Accepts a `type` discriminator so daily / monthly / backfill share the function
- Pure: no Dagster imports, no env reads

### Retry helper (decorator)

```python
# utils/utils.py
import time, functools
from typing import Callable

def retry(times: int = 3, backoff: float = 1.0, exceptions=(Exception,)):
    """Retry a function on exception with exponential backoff."""
    def deco(fn: Callable):
        @functools.wraps(fn)
        def wrapped(*args, **kwargs):
            attempt = 0
            while True:
                try:
                    return fn(*args, **kwargs)
                except exceptions:
                    attempt += 1
                    if attempt >= times:
                        raise
                    time.sleep(backoff * (2 ** (attempt - 1)))
        return wrapped
    return deco
```

Used by Resource methods, not assets directly.

## Anti-patterns

- A `helpers.py` that does everything — split by concern
- Dagster imports in utils — those functions belong in resources / assets / sensors
- Mutable module-level state (caches, counters) — pass through arguments or use a Resource
- Project-specific business logic in utils — that's per-source, belongs in the source's asset folder
- Network calls in utils — those need timeout / retry discipline that lives in a Resource
- Reading environment variables in utils — pass values in; let Resources read env
