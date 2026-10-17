"""Runs the sync Lambda handler locally: pipenv run python run_local.py"""

import json
import logging

from handler import lambda_handler

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    result = lambda_handler({}, None)
    print(json.dumps(result, indent=2))
