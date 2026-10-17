"""Runs the sync Lambda handler locally: pipenv run python src/run_local.py [--max-pages 1]"""

import argparse
import json
import logging

from handler import lambda_handler

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--query", help="OLX search query (default: toaletki)")
    parser.add_argument("--max-pages", type=int, help="stop after this many pages")
    parser.add_argument("--delay", type=float, help="seconds to wait between pages (default: 10)")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    event = {"query": args.query, "max_pages": args.max_pages, "delay": args.delay}
    result = lambda_handler({k: v for k, v in event.items() if v is not None}, None)
    print(json.dumps(result, indent=2, ensure_ascii=False))
