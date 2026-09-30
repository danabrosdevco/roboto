<#
  EXPORT - the next playtest build, in one go.

  Double-click tools\export_build.bat, or press "Export build" in the editor's
  top bar (switch it on once: Project > Project Settings > Plugins).

  What it does, in order:
    1. Works out the version: the higher of Managers\build_version.gd and the
       newest ..\Exports\*_v0.NNNx folder, plus one. 0.002a -> 0.003a.
    2. Writes it into Managers\build_version.gd. The game shows it in the
       corner of every menu and on every playtest and lab report.
    3. Exports the "Windows Desktop" preset, RELEASE, to
       ..\Exports\DataCenterWars2109_v0.003a\DataCenterWars.exe
    4. Writes build_info.txt beside it (version, date, git commit) and zips
       the folder's files into DataCenterWars2109_v0.003a.zip, in the folder.
       Extract All on that zip gives one folder with the game in it.
    5. Opens the folder.

  A failed export puts build_version.gd back and removes the half-made
  folder, so it never uses up a number. An existing folder is never touched.

  The export reads what is SAVED. The editor button saves open scenes first;
  from the .bat, save in the editor before you run it.

  Options - from a terminal: tools\export_build.bat -Hotfix
    -Version 0.010a   exactly this version
    -Hotfix           same number, next letter: 0.003a -> 0.003b
    -DebugBuild       export with debug: slower, adds a console .exe, and
                      ships the debug builds of the Jolt and DebugDraw DLLs
    -NoZip            skip the zip
    -NoOpen           don't open the folder at the end
    -DryRun           say what would happen and change nothing
    -ExportsDir path  somewhere other than ..\Exports

  This file is plain ASCII on purpose: Windows PowerShell reads a script
  without a byte-order mark as ANSI, and garbles anything fancier.
#>
param(
	[string]$Version = "",
	[switch]$Hotfix,
	[switch]$DebugBuild,
	[switch]$NoZip,
	[switch]$NoOpen,
	[switch]$DryRun,
	[string]$ExportsDir = ""
)

$ErrorActionPreference = "Stop"
$Game = "DataCenterWars2109"
$ExeName = "DataCenterWars.exe"
$Preset = "Windows Desktop"

$Project = Split-Path -Parent $PSScriptRoot
if ($ExportsDir -eq "") { $ExportsDir = Join-Path (Split-Path -Parent $Project) "Exports" }
$VersionFile = Join-Path $Project "Managers\build_version.gd"
$Utf8 = New-Object System.Text.UTF8Encoding $false

function Fail([string]$Message) {
	Write-Host ""
	Write-Host "EXPORT FAILED: $Message" -ForegroundColor Red
	exit 1
}

# -- GODOT AND TEMPLATES ------------------------
$Godot = $env:GODOT
if (-not $Godot) {
	foreach ($candidate in @(
			(Join-Path (Split-Path -Parent $Project) "Godot_v4.3-stable_win64.exe\Godot_v4.3-stable_win64_console.exe"),
			"C:\Program Files\Godot\Godot_v4.3-stable_win64_console.exe")) {
		if (Test-Path -LiteralPath $candidate) { $Godot = $candidate; break }
	}
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) {
	Fail "Godot 4.3 (the _console.exe) was not found. Set the GODOT environment variable to its path."
}
$Kind = if ($DebugBuild) { "debug" } else { "release" }
$Template = Join-Path $env:APPDATA ("Godot\export_templates\4.3.stable\windows_{0}_x86_64.exe" -f $Kind)
if (-not (Test-Path -LiteralPath $Template)) {
	Fail "the Godot 4.3 export templates are missing. Install them in the editor: Editor > Manage Export Templates."
}

# -- VERSION ------------------------------------
# 0.002a: major 0, number 002 (its width is kept), letter a.
function Parse-Version([string]$Text) {
	if ($Text -match '^(\d+)\.(\d+)([a-z]?)$') {
		return [pscustomobject]@{
			Major = [int]$Matches[1]; Number = [int]$Matches[2]; Width = $Matches[2].Length
			Letter = $Matches[3]; Text = $Text
		}
	}
	return $null
}
function Format-Version([int]$Major, [int]$Number, [int]$Width, [string]$Letter) {
	return "{0}.{1}{2}" -f $Major, $Number.ToString().PadLeft($Width, '0'), $Letter
}

$VersionText = [IO.File]::ReadAllText($VersionFile)
if ($VersionText -notmatch '(?m)^const VERSION := "([^"]*)"') { Fail "no 'const VERSION' line in $VersionFile" }
$known = @()
$exported = @{}
$fromFile = Parse-Version $Matches[1]
if ($fromFile) { $known += $fromFile }
if (Test-Path -LiteralPath $ExportsDir) {
	foreach ($dir in Get-ChildItem -LiteralPath $ExportsDir -Directory) {
		if ($dir.Name -match '_v(\d+\.\d+[a-z]?)$') {
			$found = Parse-Version $Matches[1]
			if ($found) { $known += $found; $exported[$found.Text] = $dir.Name }
		}
	}
}
# Zero-padded so the sort is numeric; "" sorts before "a", "a" before "b".
$latest = $known | Sort-Object { "{0:D6}.{1:D9}.{2}" -f $_.Major, $_.Number, $_.Letter } | Select-Object -Last 1

if ($Version -ne "") {
	$next = Parse-Version $Version
	if (-not $next) { Fail "'$Version' is not a version like 0.003a" }
	$NextText = $next.Text
} elseif (-not $latest) {
	$NextText = "0.001a"
} elseif ($Hotfix) {
	if ($latest.Letter -eq "z") { Fail "$($latest.Text) has no letter after z; pass -Version instead." }
	$letter = if ($latest.Letter -eq "") { "a" } else { [string][char]([int][char]$latest.Letter + 1) }
	$NextText = Format-Version $latest.Major $latest.Number $latest.Width $letter
} else {
	$letter = if ($latest.Letter -eq "") { "a" } else { $latest.Letter }
	$NextText = Format-Version $latest.Major ($latest.Number + 1) $latest.Width $letter
}

$Folder = Join-Path $ExportsDir ("{0}_v{1}" -f $Game, $NextText)
$ExePath = Join-Path $Folder $ExeName
$PckPath = [IO.Path]::ChangeExtension($ExePath, ".pck")
$ZipName = "{0}_v{1}.zip" -f $Game, $NextText

Write-Host "DATA CENTER WARS 2109 - export"
Write-Host ("  last version  {0}" -f $(if ($latest) { $latest.Text } else { "(none)" }))
Write-Host "  this version  $NextText ($Kind)"
Write-Host "  folder        $Folder"
if (Test-Path -LiteralPath $Folder) { Fail "that folder already exists. Nothing was changed." }
if ($exported.ContainsKey($NextText)) { Fail ("v{0} was already exported, as {1}. Nothing was changed." -f $NextText, $exported[$NextText]) }
if ($DryRun) {
	Write-Host ""
	Write-Host "Dry run: nothing was changed."
	exit 0
}

# -- STAMP, THEN EXPORT -------------------------
$today = Get-Date -Format "yyyy-MM-dd"
$stamped = [regex]::Replace($VersionText, '(?m)^const VERSION := "[^"]*"', "const VERSION := `"$NextText`"")
$stamped = [regex]::Replace($stamped, '(?m)^const EXPORTED := "[^"]*"', "const EXPORTED := `"$today`"")
[IO.File]::WriteAllText($VersionFile, $stamped, $Utf8)

New-Item -ItemType Directory -Path $Folder -Force | Out-Null
$started = Get-Date
Write-Host ""
Write-Host "Exporting, a minute or two..."
# Continue, not Stop: Godot writes progress to stderr, and Windows PowerShell
# can turn a native program's stderr into errors when Stop is set.
$ErrorActionPreference = "Continue"
$mode = if ($DebugBuild) { "--export-debug" } else { "--export-release" }
& $Godot --headless --path $Project $mode $Preset $ExePath
$code = $LASTEXITCODE
$ErrorActionPreference = "Stop"

if ($code -ne 0 -or -not (Test-Path -LiteralPath $ExePath) -or -not (Test-Path -LiteralPath $PckPath)) {
	[IO.File]::WriteAllText($VersionFile, $VersionText, $Utf8)
	# Only ever the folder this run made: it did not exist a minute ago.
	Remove-Item -LiteralPath $Folder -Recurse -Force -ErrorAction SilentlyContinue
	Fail ("Godot exited with code {0}. build_version.gd is back to {1} and the folder was removed." -f $code, $fromFile.Text)
}

# -- BUILD INFO ---------------------------------
# Which code this was, for when a playtester reports something.
$source = "git not found"
if (Get-Command git -ErrorAction SilentlyContinue) {
	$ErrorActionPreference = "Continue"
	$commit = (& git -C $Project rev-parse --short HEAD 2>$null | Select-Object -First 1)
	$changes = @(& git -C $Project status --porcelain 2>$null).Count
	$ErrorActionPreference = "Stop"
	if ($commit) {
		$source = "git $commit" + $(if ($changes -gt 0) { " + $changes uncommitted change(s)" } else { "" })
	}
}
$info = @(
	"Data Center Wars 2109  v$NextText ($Kind)",
	("Exported  {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm")),
	"Source    $source",
	"Engine    Godot 4.3-stable"
)
[IO.File]::WriteAllLines((Join-Path $Folder "build_info.txt"), [string[]]$info, $Utf8)

# -- ZIP ----------------------------------------
# Built beside the folder and moved in, so it can never try to include itself.
$zipPath = Join-Path $Folder $ZipName
if (-not $NoZip) {
	Write-Host "Zipping..."
	Add-Type -AssemblyName System.IO.Compression
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$partial = Join-Path $ExportsDir ($ZipName + ".partial")
	if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
	[IO.Compression.ZipFile]::CreateFromDirectory($Folder, $partial, [IO.Compression.CompressionLevel]::Optimal, $false)
	Move-Item -LiteralPath $partial -Destination $zipPath
}

$seconds = [int]((Get-Date) - $started).TotalSeconds
Write-Host ""
Write-Host "EXPORTED v$NextText ($Kind) in ${seconds}s" -ForegroundColor Green
Write-Host "  $Folder"
if (-not $NoZip) { Write-Host ("  {0}  {1:N0} MB" -f $ZipName, ((Get-Item -LiteralPath $zipPath).Length / 1MB)) }
Write-Host "  Managers\build_version.gd now says ${NextText} - commit it with this build."
if (-not $NoOpen) { Invoke-Item -LiteralPath $Folder }
