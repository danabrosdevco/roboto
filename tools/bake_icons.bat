@echo off
rem Double-click to redraw the line-art icons in res://icons from the models.
rem A small Godot window opens for a few seconds while it renders.
set GODOT_EXE=%~dp0..\..\Godot_v4.3-stable_win64.exe\Godot_v4.3-stable_win64_console.exe
if not "%GODOT%"=="" set GODOT_EXE=%GODOT%
"%GODOT_EXE%" --path "%~dp0.." --windowed --resolution 320x180 --script res://tools/bake_icons.gd
echo.
pause
