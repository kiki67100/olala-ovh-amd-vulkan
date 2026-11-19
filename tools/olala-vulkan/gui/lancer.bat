@echo off
rem Lance le chat Olala sur GPU (Vulkan) et ouvre http://localhost:7861
rem Fermer cette fenetre (ou Ctrl+C) arrete le chat et libere le GPU.
rem Dossier de travail : OLALA_WIN_ROOT (defaut C:\olala).
title Olala GUI Vulkan
cd /d "%~dp0"
set "PYCMD=python"
where py >nul 2>&1
if not errorlevel 1 set "PYCMD=py -3"
%PYCMD% app.py --open %*
if errorlevel 1 pause
