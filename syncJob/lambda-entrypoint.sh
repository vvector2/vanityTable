#!/bin/sh
# On AWS the Lambda service provides AWS_LAMBDA_RUNTIME_API. Locally it is unset,
# so the runtime interface client is started behind the emulator instead.
if [ -z "${AWS_LAMBDA_RUNTIME_API}" ]; then
  exec /usr/local/bin/aws-lambda-rie python3 -m awslambdaric "$@"
else
  exec python3 -m awslambdaric "$@"
fi
