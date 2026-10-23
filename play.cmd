@echo off
REM ---------------------------------------------------------------------
REM  PLAY DATA CENTER WARS FROM SOURCE.
REM
REM  No export and no editor. Godot runs the project straight off disk,
REM  which is the same thing the editor's play button does -- so this plays
REM  WHATEVER IS ON DISK RIGHT NOW, uncommitted work included.
REM
REM    play.cmd                   play it. This is your real campaign save.
REM    play.cmd -- --no-save      play it, writing no campaign at all.
REM    play.cmd --windowed --resolution 1152x648
REM
REM  Anything you pass goes to GODOT. A bare -- sends what follows to the
REM  GAME instead, which is why --no-save needs two of them.
REM
REM  THE PLAIN .exe, NOT _console.exe. The console build exists so a script
REM  can read the output and it drags a terminal along behind the game. Set
REM  GODOT to override the path if the binary ever moves.
REM
REM  ONE PREREQUISITE: the .godot\ import cache, which the editor builds.
REM  If it is ever deleted, open the project in the editor once to rebuild
REM  it -- this cannot do that for you.
REM
REM  THE EDITOR MAY BE OPEN, but it is not free: both processes share that
REM  import cache and the same saves under user://, so a session you play
REM  here overwrites the campaign an editor run was using. -- --no-save
REM  avoids that half of it.
REM ---------------------------------------------------------------------

setlocal
if "%GODOT%"=="" set "GODOT=D:\Godot Games\Godot_v4.3-stable_win64.exe\Godot_v4.3-stable_win64.exe"

if not exist "%GODOT%" (
	echo Godot was not found at:
	echo    %GODOT%
	echo.
	echo Set GODOT to the binary and run this again.
	pause
	exit /b 1
)

REM %~dp0 is this file's own folder, so the shortcut works from anywhere.
"%GODOT%" --path "%~dp0." %*

REM HELD OPEN ON FAILURE ONLY. A double-click that dies instantly tells you
REM nothing; a clean quit should not leave a console sitting there.
if errorlevel 1 (
	echo.
	echo Godot exited with an error ^(code %errorlevel%^).
	pause
)
endlocal
