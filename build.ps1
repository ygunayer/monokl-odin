param (
  [Parameter(Position=0)]
  [string]$Command,

  [Parameter(Position=1, ValueFromRemainingArguments=$true)]
  [string[]]$RemainingArgs = @()
)

$CompileFlags = "-out=bin/monokl.exe"
$DebugFlags = "-o:none -debug"
$ReleaseFlag = "-subsystem:windows"

New-Item -ItemType Directory -Path bin -Force | Out-Null

function Show-Help {
  Write-Host ""
  Write-Host "Usage: .\build.ps1 <command> [args]"
  Write-Host ""
  Write-Host "Commands:"
  Write-Host "   compile, c       [compile-flags]    (Default) Compiles the project with the given flags"
  Write-Host "   run, r           [compile-flags]    First compiles, then runs the project"
  Write-Host "   help, h                           Shows this help text"
  Write-Host ""
  Write-Host "Values for [compile-flags]:"
  Write-Host "   --release, -r    Enables release mode, preventing debug symbols from being emitted and adding optimizations."
  Write-Host ""
}

function Run-Odin {
  param (
    [string]$cmd
  )

  $flags = ""

  $isRelease = $false
  foreach ($arg in $RemainingArgs) {
    if ($arg -eq "-r" -or $arg -eq "--release") {
      $isRelease = $true
      break
    }
  }

  if ($isRelease) {
    Write-Host "Compiling in Release mode"
    $flags = $ReleaseFlag
  } else {
    Write-Host "Compiling in Debug mode"
    $flags = $DebugFlags
  }

  cmd /c "odin.exe $cmd src\ $CompileFlags $flags"

  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not $Command) {
  Write-Host "No command specified"
  Show-Help
  exit 1
}

# Normalize command aliases
switch ($Command.ToLower()) {
  { $_ -in "c", "compile" } { $Command = "compile" }
  { $_ -in "r", "run" } { $Command = "run" }
}

switch ($Command) {
  "compile" {
    Run-Odin "build"
    exit 0
  }

  "run" {
    Run-Odin "run"
    exit 0
  }

  default {
    Write-Host "Unknown command `"$Command`""
    Show-Help
    exit 1
  }
}
