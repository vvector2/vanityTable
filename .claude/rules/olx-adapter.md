---
paths:
  - "syncJob/**/adapter/**"
  - "syncJob/**/olx*.py"
---

# OLX source adapter

- The adapter is the only code that knows OLX. It returns normalized listings: `olx_id`, `title`, `description` (may be `None`), `price` (number or `None`), `url`, `photo_urls`, `is_active`. Nothing outside the adapter may parse OLX HTML or JSON.
- Fetching rules are mandatory:
  - one request stream, no parallelism or async fan-out
  - a reasonable, honest User-Agent
  - stop on HTTP 429, captcha or any fetch error by raising; no retries within a run
  - never circumvent blocks: no proxy rotation, header spoofing or captcha solving
- Fetch a listing page (for the description) only for listings not already known.
- Tests use saved fixture pages, never live OLX requests.
