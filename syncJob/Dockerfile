# Sync Lambda container image. Playwright's image ships Chromium and its system
# libraries, which do not fit in a zip package or layer (250 MB limit).
# Build: docker build --platform linux/amd64 --provenance=false -t toaletka-sync .
FROM mcr.microsoft.com/playwright/python:v1.64.0-noble

ENV LAMBDA_TASK_ROOT=/var/task \
    PYTHONPATH=/var/task \
    PYTHONUNBUFFERED=1 \
    # Lambda's file system is read-only outside /tmp; Chromium writes to $HOME.
    HOME=/tmp

WORKDIR /var/task

COPY requirements-lambda.txt .
RUN python3 -m pip install --no-cache-dir --break-system-packages -r requirements-lambda.txt

# Lambda Runtime Interface Emulator, so the same image runs locally with `docker run`.
ADD https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie /usr/local/bin/aws-lambda-rie
COPY lambda-entrypoint.sh /lambda-entrypoint.sh
RUN chmod 755 /usr/local/bin/aws-lambda-rie /lambda-entrypoint.sh

COPY src/ ./

ENTRYPOINT ["/lambda-entrypoint.sh"]
CMD ["handler.lambda_handler"]
