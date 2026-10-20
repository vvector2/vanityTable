# Sync Lambda container image. Chromium and its system libraries do not fit in a zip
# package or layer (250 MB limit), hence a container image.
# Only Chromium's headless shell is installed (the job always runs headless on Lambda).
# Its system libraries are listed by hand instead of `playwright install --with-deps`, which
# also pulls in Xvfb, Mesa (with a 112 MB LLVM) and CJK fonts the headless shell does not use.
# The list is what `ldd chrome-headless-shell` resolves to; check it when upgrading playwright.
# Build: docker build --platform linux/amd64 --provenance=false -t toaletka-sync .
FROM python:3.12-slim-bookworm

ENV LAMBDA_TASK_ROOT=/var/task \
    PYTHONPATH=/var/task \
    PYTHONUNBUFFERED=1 \
    # Outside $HOME: Lambda's file system is read-only except /tmp.
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    # Chromium writes to $HOME.
    HOME=/tmp

WORKDIR /var/task

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libdbus-1-3 libdrm2 libgbm1 \
        libglib2.0-0 libnspr4 libnss3 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 \
        libxfixes3 libxi6 libxkbcommon0 libxrandr2 fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

COPY requirements-lambda.txt .
RUN python3 -m pip install --no-cache-dir -r requirements-lambda.txt \
    && python3 -m playwright install --only-shell chromium

# Lambda Runtime Interface Emulator, so the same image runs locally with `docker run`.
ADD https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie /usr/local/bin/aws-lambda-rie
COPY lambda-entrypoint.sh /lambda-entrypoint.sh
RUN chmod 755 /usr/local/bin/aws-lambda-rie /lambda-entrypoint.sh

COPY src/ ./

ENTRYPOINT ["/lambda-entrypoint.sh"]
CMD ["handler.lambda_handler"]
