<#
  PowerShell trampoline for bootstrap.sh. Lets Windows users do the native:
    irm https://raw.githubusercontent.com/AdityaMunot/trove/master/bootstrap.ps1 | iex
  Requires bash on PATH (Git for Windows installs it by default).
  All flags forward to bootstrap.sh (e.g. uninstall, --no-todo, --dry-run).
#>

[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments)][string[]]$Forward)

$ErrorActionPreference = 'Stop'

$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) {
    throw "bash not found on PATH. Install Git for Windows (which ships Git Bash), or run the bootstrap.sh one-liner from a Git Bash terminal."
}

# Local clone? Use the sibling bootstrap.sh directly.
if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'bootstrap.sh'))) {
    & $bash.Source (Join-Path $PSScriptRoot 'bootstrap.sh') @Forward
    exit $LASTEXITCODE
}

# Remote one-liner (irm | iex): download bootstrap.sh to a temp file and run.
$tmp = [System.IO.Path]::GetTempFileName()
try {
    Invoke-WebRequest -UseBasicParsing `
        -Uri 'https://raw.githubusercontent.com/AdityaMunot/trove/master/bootstrap.sh' `
        -OutFile $tmp
    & $bash.Source $tmp @Forward
    exit $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
}
