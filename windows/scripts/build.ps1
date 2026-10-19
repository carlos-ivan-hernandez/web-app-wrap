<#
.SYNOPSIS
  Builds Web App Wrap for Windows into "dist\Web App Wrap".
.PARAMETER Arch
  x64 (default) or arm64.
.PARAMETER Install
  Also install it for the current user (see install.ps1).
.EXAMPLE
  .\scripts\build.ps1 -Install
#>
param(
    [ValidateSet('x64', 'arm64')] [string] $Arch = 'x64',
    [switch] $Install
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root 'dist\Web App Wrap'
$rid = "win-$Arch"
$platform = @{ x64 = 'x64'; arm64 = 'ARM64' }[$Arch]

# Draw Web App Wrap's own icon with the same renderer used for wrapped apps.
dotnet run --project "$root\src\waw" -c Release -- icon --name 'Web App Wrap' --out "$root\src\WebAppWrap\Assets\AppIcon.ico"
if ($LASTEXITCODE) { throw 'Drawing the app icon failed.' }

if (Test-Path $out) { Remove-Item -Recurse -Force $out }

# WebAppWrap.exe (the window, and the program every wrapped app runs) and waw.exe (the command line)
# share one folder. Both are self-contained: nothing else needs to be installed.
dotnet publish "$root\src\WebAppWrap\WebAppWrap.csproj" -c Release -r $rid -p:Platform=$platform -o $out
if ($LASTEXITCODE) { throw 'Building WebAppWrap.exe failed.' }
dotnet publish "$root\src\waw\waw.csproj" -c Release -r $rid -o $out
if ($LASTEXITCODE) { throw 'Building waw.exe failed.' }

Write-Host "Built $out"
if ($Install) { & (Join-Path $PSScriptRoot 'install.ps1') -Source $out }
