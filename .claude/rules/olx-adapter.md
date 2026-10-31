---
paths:
  - "syncJob/**/adapter/**"
  - "syncJob/**/olx*.py"
---

# OLX source adapter

- The adapter is the only code that knows OLX. It returns normalized listings: `olx_id`, `title`, `description` (may be `None`), `price` (number or `None`), `url`, `photo_urls`, `is_active`. Nothing outside the adapter may parse OLX HTML or JSON.
- Fetching rules are mandatory:
  - one request stream, no parallelism or async fan-out; results pages about 15 s apart plus a random 0 to 5 s
  - a reasonable, honest User-Agent
  - stop on HTTP 429 or captcha by raising; no retries
  - on HTTP 403, 5xx, a timeout or a network error, reload the same page after a random wait of 30 to 60 s, up to 3 attempts in all; then stop by raising. Never restart the whole run
  - log every failed response (status, headers, title, start of the body) so blocks can be diagnosed
  - never circumvent blocks: no proxy rotation, header spoofing or captcha solving
- Fetch a listing page (for the description) only for listings not already known.
- Tests use saved fixture pages, never live OLX requests.
