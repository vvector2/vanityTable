"""Browser bot that loads OLX search results and saves every listing as JSON.

Spike tool, run locally: pipenv run python olx_browser_bot.py --query toaletki

It drives headless Chromium through every results page of
https://www.olx.pl/oferty/q-<query>/ and reads the listing data the OLX app
embeds in `window.__PRERENDERED_STATE__`. Each ad is normalized to the adapter
contract in docs/architecture.md (section 3) plus a few non-personal extras.

Fetching rules (.claude/rules/olx-adapter.md):
- one page at a time, with a pause between pages
- an honest User-Agent
- stop on HTTP 429, captcha or any fetch error; no retries
- seller data (user, contact, map coordinates) is never stored
"""

import argparse
import html
import json
import logging
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote

from playwright.sync_api import Page, Route, sync_playwright

logger = logging.getLogger("olx_browser_bot")

BASE_URL = "https://www.olx.pl/oferty/q-{query}/"
USER_AGENT = "ToaletkaBot/0.1 (private, non-commercial listing watcher; Playwright Chromium)"
# The bot reads data, not pixels: skipping these keeps the load on OLX and its CDN low.
BLOCKED_RESOURCES = {"image", "media", "font"}
CAPTCHA_MARKERS = ("captcha", "cf-challenge", "are you a robot", "jestes robotem", "jesteś robotem")
STATE_VAR = "window.__PRERENDERED_STATE__"


class FetchStopped(Exception):
    """Raised when the run must stop: HTTP error, 429, captcha or missing data."""


def search_url(query: str, page_number: int) -> str:
    url = BASE_URL.format(query=quote(query))
    return url if page_number == 1 else f"{url}?page={page_number}"


def clean_description(raw: str | None) -> str | None:
    if raw is None:
        return None
    text = re.sub(r"<br\s*/?>", "", raw)
    text = re.sub(r"<[^>]+>", "", text)
    return html.unescape(text).strip()


def parse_price(price: dict[str, Any] | None) -> tuple[float | None, str | None]:
    if not price:
        return None, None
    if price.get("free"):
        return 0, "PLN"
    regular = price.get("regularPrice") or {}
    return regular.get("value"), regular.get("currencyCode")


def normalize_ad(ad: dict[str, Any]) -> dict[str, Any]:
    raw_price = ad.get("price") or {}
    price, currency = parse_price(raw_price)
    location = ad.get("location") or {}
    return {
        "olx_id": str(ad["id"]),
        "title": ad.get("title"),
        "description": clean_description(ad.get("description")),
        "price": price,
        "currency": currency,
        "price_label": raw_price.get("displayValue"),
        "negotiable": (raw_price.get("regularPrice") or {}).get("negotiable"),
        "url": ad.get("url"),
        "photo_urls": ad.get("photos") or [],
        "is_active": bool(ad.get("isActive")),
        "status": ad.get("status"),
        "is_promoted": bool(ad.get("isPromoted")),
        "is_business": bool(ad.get("isBusiness")),
        "category_id": (ad.get("category") or {}).get("id"),
        "params": {p["key"]: p.get("value") for p in ad.get("params") or [] if "key" in p},
        "city": location.get("cityName"),
        "region": location.get("regionName"),
        "created_time": ad.get("createdTime"),
        "last_refresh_time": ad.get("lastRefreshTime"),
        "valid_to_time": ad.get("validToTime"),
    }


def read_state(page: Page, document_html: str) -> dict[str, Any]:
    """Returns the app state embedded in the server HTML.

    The app deletes the variable and its script tag after hydration, so the
    state is taken from the navigation response body, not the live DOM.
    """
    marker = document_html.find(STATE_VAR)
    if marker == -1:
        raise FetchStopped(f"{STATE_VAR} not found on {page.url}")
    raw, _ = json.JSONDecoder().raw_decode(document_html, document_html.index('"', marker))
    return json.loads(raw)


def check_for_captcha(page: Page) -> None:
    text = (page.title() + " " + page.inner_text("body")[:5000]).lower()
    if any(marker in text for marker in CAPTCHA_MARKERS):
        raise FetchStopped(f"Captcha or bot challenge on {page.url}")


def load_results_page(page: Page, url: str) -> dict[str, Any]:
    logger.info("Loading %s", url)
    response = page.goto(url, wait_until="domcontentloaded", timeout=60_000)
    if response is None:
        raise FetchStopped(f"No response for {url}")
    if response.status == 429:
        raise FetchStopped(f"HTTP 429 Too Many Requests on {url}")
    if response.status >= 400:
        raise FetchStopped(f"HTTP {response.status} on {url}")
    check_for_captcha(page)
    listing = (read_state(page, response.text()).get("listing") or {}).get("listing")
    if not listing or "ads" not in listing:
        raise FetchStopped(f"Listing data missing in app state on {url}")
    return listing


def block_heavy_resources(route: Route) -> None:
    if route.request.resource_type in BLOCKED_RESOURCES:
        route.abort()
    else:
        route.continue_()


def scrape(query: str, delay: float, max_pages: int | None, headed: bool) -> dict[str, Any]:
    result: dict[str, Any] = {
        "query": query,
        "source_url": search_url(query, 1),
        "started_at": datetime.now(timezone.utc).isoformat(),
        "finished_at": None,
        "complete": False,
        "error": None,
        "reported_total": None,
        "reported_visible": None,
        "total_pages": None,
        "pages_fetched": 0,
        "listing_count": 0,
        "listings": [],
    }
    # Promoted ads repeat across pages, so listings are de-duplicated by OLX ID.
    seen: dict[str, dict[str, Any]] = {}

    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=not headed)
        context = browser.new_context(user_agent=USER_AGENT, locale="pl-PL")
        context.route("**/*", block_heavy_resources)
        page = context.new_page()
        try:
            page_number = 1
            while True:
                listing = load_results_page(page, search_url(query, page_number))
                result["pages_fetched"] = page_number
                if page_number == 1:
                    result["reported_total"] = listing.get("totalElements")
                    result["reported_visible"] = listing.get("visibleElements")
                    result["total_pages"] = listing.get("totalPages")

                new_ads = 0
                for ad in listing["ads"]:
                    olx_id = str(ad["id"])
                    if olx_id not in seen:
                        seen[olx_id] = normalize_ad(ad)
                        new_ads += 1
                logger.info(
                    "Page %d: %d ads, %d new, %d total", page_number, len(listing["ads"]), new_ads, len(seen)
                )

                last_page = min(result["total_pages"] or page_number, max_pages or sys.maxsize)
                if page_number >= last_page or not listing["ads"]:
                    break
                page_number += 1
                time.sleep(delay)
            result["complete"] = True
        except FetchStopped as exc:
            logger.error("Stopped: %s", exc)
            result["error"] = str(exc)
        except Exception as exc:  # noqa: BLE001 - any failure stops the run; partial data is kept
            logger.exception("Stopped on unexpected error")
            result["error"] = f"{type(exc).__name__}: {exc}"
        finally:
            browser.close()

    result["listings"] = list(seen.values())
    result["listing_count"] = len(seen)
    result["finished_at"] = datetime.now(timezone.utc).isoformat()
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--query", default="toaletki", help="OLX search query (default: toaletki)")
    parser.add_argument("--out", type=Path, default=Path("output/listings.json"), help="output JSON file")
    parser.add_argument("--delay", type=float, default=10.0, help="seconds to wait between pages (default: 10)")
    parser.add_argument("--max-pages", type=int, default=None, help="stop after this many pages")
    parser.add_argument("--headed", action="store_true", help="show the browser window")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    result = scrape(args.query, args.delay, args.max_pages, args.headed)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    logger.info("Saved %d listings to %s (complete=%s)", result["listing_count"], args.out, result["complete"])
    return 0 if result["complete"] else 1


if __name__ == "__main__":
    sys.exit(main())
