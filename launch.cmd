@echo off
rem Runs the app locally. See scripts\launch.ps1. Usage: launch [-UiPort 5174]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\launch.ps1" %*
