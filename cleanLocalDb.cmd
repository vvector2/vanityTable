@echo off
rem Empties all DynamoDB tables in the local LocalStack. See scripts\local\clean-local-db.ps1. Usage: cleanLocalDb
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\local\clean-local-db.ps1" %*
