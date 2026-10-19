---
paths:
  - "syncJob/**/*.py"
---

# Python backend (Lambda)

- Keep handlers thin: parse the event, call plain functions, return. Business logic must be testable without AWS.
- Read the fuzzy threshold, exceptions list and search settings from SSM at runtime. Never hard-code them.
- Sync must be safe on failure:
  - a known listing's `status` and decision are never overwritten by sync
  - listings are marked `expired` only after a fully successful fetch
  - `META#sync.last_success_at` is written last, only when everything succeeded
- Matching: split title and description into words, normalize case and Polish diacritics, score each word against "toaletka" with `rapidfuzz`, store the best score as `match_score`, and skip words on the exceptions list.
- Use `boto3` from the Lambda runtime; do not bundle it.
- Use type hints. Use `pytest` for tests and `moto` or stubs for AWS.
