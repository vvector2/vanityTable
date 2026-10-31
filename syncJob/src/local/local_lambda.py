"""Serves the sync handler behind the Lambda Invoke API, so a local Listings API can start scans.

Started by launch (scripts/local/launch.ps1): pipenv run python -m local.local_lambda [--port 9001]
(from syncJob/src, so the handler and its packages import as they do on Lambda)
The API reaches it through AWS_ENDPOINT_URL_LAMBDA and invokes it like the deployed function
(POST /2015-03-31/functions/<name>/invocations). "Event" invokes return 202 at once and run in
the background; other invocation types wait for the result. Runs never overlap, like one
request stream to OLX on AWS.
"""

import argparse
import json
import logging
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from handler import lambda_handler

INVOKE_PATH = re.compile(r"^/2015-03-31/functions/[^/]+/invocations$")

logger = logging.getLogger(__name__)
run_lock = threading.Lock()


def run(event: dict) -> dict:
    with run_lock:
        return lambda_handler(event, None)


def run_in_background(event: dict) -> None:
    try:
        run(event)
    except Exception:
        logger.exception("Sync run failed")


class InvokeHandler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:
        if not INVOKE_PATH.match(self.path.split("?")[0]):
            self.send_json(404, {"Type": "User", "message": f"Unknown path {self.path}"})
            return
        length = int(self.headers.get("Content-Length") or 0)
        event = json.loads(self.rfile.read(length) or b"{}")

        if self.headers.get("X-Amz-Invocation-Type") == "Event":
            logger.info("Async invoke: %s", event)
            threading.Thread(target=run_in_background, args=(event,), daemon=True).start()
            self.send_json(202, None)
            return

        logger.info("Sync invoke: %s", event)
        try:
            self.send_json(200, run(event))
        except Exception as error:
            logger.exception("Sync run failed")
            self.send_json(200, {"errorMessage": str(error), "errorType": type(error).__name__}, function_error=True)

    def send_json(self, status: int, body: object, function_error: bool = False) -> None:
        data = b"" if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        if function_error:
            self.send_header("X-Amz-Function-Error", "Unhandled")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args: object) -> None:
        logger.debug(format, *args)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=9001)
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [sync] %(message)s")
    server = ThreadingHTTPServer(("127.0.0.1", args.port), InvokeHandler)
    logger.info("Local sync Lambda listening on http://localhost:%d", args.port)
    server.serve_forever()
