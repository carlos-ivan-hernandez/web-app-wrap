<#
.SYNOPSIS
  Installs Web App Wrap for the current user: copies it to %LOCALAPPDATA%\Programs\Web App Wrap,
  adds it to the Start menu, and adds that folder to your PATH so "waw" works in any terminal.
.PARAMETER Source
  The built folder. Defaults to "dist\Web App Wrap" (see build.ps1).
#>
param(
    [string] $Source = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\Web App Wrap')
)
$ErrorActionPreference = 'Stop'
$target = Join-Path $env:LOCALAPPDATA 'Programs\Web App Wrap'
if (-not (Test-Path (Join-Path $Source 'WebAppWrap.exe'))) { throw "No build found in $Source. Run scripts\build.ps1 first." }

# Wrapped apps run WebAppWrap.exe from the install folder, so its files are in use while any are open.
$running = Get-Process -Name WebAppWrap, waw -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($target, [StringComparison]::OrdinalIgnoreCase) }
if ($running) { throw "Close Web App Wrap and every wrapped app first; they run from $target." }

# Installing to the same place every time keeps existing wrapped apps' shortcuts working.
if (Test-Path $target) { Remove-Item -Recurse -Force $target }
New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
Copy-Item -Recurse $Source $target

$exe = Join-Path $target 'WebAppWrap.exe'
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Web App Wrap.lnk'))
$link.TargetPath = $exe
$link.WorkingDirectory = $target
$link.IconLocation = "$exe,0"
$link.Description = 'Turn web apps into Windows apps with tabs'
$link.Save()

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not (($userPath -split ';') -contains $target)) {
    [Environment]::SetEnvironmentVariable('Path', (($userPath.TrimEnd(';'), $target) -join ';').TrimStart(';'), 'User')
    Write-Host "Added $target to your PATH. Open a new terminal to use waw."
}
Write-Host "Installed Web App Wrap to $target"
