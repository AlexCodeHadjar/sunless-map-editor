@echo off
rem Запуск редактора карт SunLess. Godot 4.7: переменная GODOT, рядом с редактором или D:\Godot_v4.7.2-stable_win64.exe
chcp 65001 >nul
set "HERE=%~dp0"
if defined GODOT goto run
if exist "%HERE%godot\Godot_v4.7.2-stable_win64.exe" set "GODOT=%HERE%godot\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT if exist "D:\Godot_v4.7.2-stable_win64.exe" set "GODOT=D:\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT for %%G in (godot.exe godot4.exe) do if not defined GODOT for /f "delims=" %%P in ('where %%G 2^>nul') do set "GODOT=%%P"
if not defined GODOT (
  echo Не найден Godot 4.7. Укажите путь: set GODOT=C:\путь\Godot_v4.7.2-stable_win64.exe
  pause
  exit /b 1
)
:run
start "" "%GODOT%" --path "%HERE%." -- %*
