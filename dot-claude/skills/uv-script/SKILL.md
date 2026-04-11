---
name: uv-script
description: Use when writing any standalone Python script, one-off utility, or when tempted to use `python3 -c`. Covers PEP 723 inline metadata, uv shebang, and dependency declaration.
---

## The Pattern

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "requests>=2.31",
#   "rich>=13.0",
# ]
# ///

import sys
# ... script body
```

Run with: `uv run script.py` or just `./script.py` (if chmod +x)

## No-Dependency Script

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
```

## Instead of `python3 -c`

When tempted to write:
```bash
python3 -c "import json, sys; data = json.load(sys.stdin); print(data['key'])"
```

Write a proper script instead, OR use `jq` for JSON (preferred for simple transforms).

**When jq is enough** (prefer this):
```bash
echo '{"key": "value"}' | jq '.key'
cat file.json | jq '.items[] | select(.active == true) | .name'
```

**When a script is needed** (use uv):
```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
import json, sys
data = json.load(sys.stdin)
print(data['key'])
```

## Common Packages (copy-paste ready)

| Package | Use |
|---------|-----|
| `requests` | HTTP calls |
| `rich` | pretty terminal output |
| `pydantic` | data validation |
| `typer` | CLI argument parsing |
| `httpx` | async HTTP |
| `python-dotenv` | .env loading |

## uvx for One-Off Tools

For running Python tools without installing:
```bash
uvx ruff check .
uvx black --check .
uvx mypy src/
```

## Script vs Tool Decision

| Need | Use |
|------|-----|
| Transform JSON | `jq` |
| Quick calc/string | Shell arithmetic or `awk` |
| Complex logic, reusable | uv script with PEP 723 |
| Install a CLI tool | `uvx` or `uv tool install` |
| Never use | `python3 -c`, `pip install` |
