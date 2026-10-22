@echo off
rem Syncs the first OLX page into the running local app. See scripts\local\quick-sync.ps1. Usage: quickSync [-Pages 1]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\local\quick-sync.ps1" %*
