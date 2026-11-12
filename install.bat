@echo off
setlocal

rem Usage: install.bat [WoW install dir]   (default: D:\World of Warcraft)
set "WOW=%~1"
if "%WOW%"=="" set "WOW=D:\Program Files (x86)\World of Warcraft"

set "ADDONS=%WOW%\_forever_\Interface\AddOns"
set "SRC=%~dp0WhatMats"
set "LINK=%ADDONS%\WhatMats"

if not exist "%ADDONS%\" (
  echo AddOns folder not found: "%ADDONS%"
  echo Pass your WoW folder: install.bat "X:\path\to\World of Warcraft"
  exit /b 1
)

if exist "%LINK%" (
  echo Already exists: "%LINK%"
  echo Remove it with: rmdir "%LINK%"
  exit /b 1
)

mklink /J "%LINK%" "%SRC%"
