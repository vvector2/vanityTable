<#
.SYNOPSIS
  Empties every DynamoDB table in the local LocalStack.

.DESCRIPTION
  Usage: cleanLocalDb   (cleanLocalDb.cmd in the repo root calls this script)
  Needs the app running (launch.cmd): deletes each table, then reruns the init scripts in
  localstack-init, so the tables come back empty with their indexes. The API keeps working.
#>

$ErrorActionPreference = "Stop"
$container = "toaletka-local-localstack-1"

# No double quotes inside: Windows PowerShell would strip them on the way to wsl.
$command = 'for t in $(awslocal dynamodb list-tables --query TableNames --output text); do ' +
    'echo Deleting table $t; awslocal dynamodb delete-table --table-name $t > /dev/null; ' +
    'awslocal dynamodb wait table-not-exists --table-name $t; done; ' +
    'for f in /etc/localstack/init/ready.d/*.sh; do bash $f; done'

Write-Host "==> Emptying the LocalStack DynamoDB tables" -ForegroundColor Cyan
wsl -e docker exec $container sh -c $command
if ($LASTEXITCODE -ne 0) { throw "Cleaning failed (is the app running? start it with launch.cmd)" }
