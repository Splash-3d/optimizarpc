@echo off
chcp 65001 >nul
title TURBO PC - Optimizador
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OptimizarPC.ps1"

echo.
echo === Optimizador cerrado. Pulsa una tecla para salir ===
pause >nul
