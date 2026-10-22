@echo off
rem Runs the app locally. See scripts\local\launch.ps1. Usage: launch [-UiPort 5174]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\local\launch.ps1" %*
