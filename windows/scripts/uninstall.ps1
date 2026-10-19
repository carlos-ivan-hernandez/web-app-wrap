<#
.SYNOPSIS
  Removes Web App Wrap: the program, its Start menu shortcut and its PATH entry.
.PARAMETER RemoveApps
  Also remove every wrapped app: their Start menu and desktop shortcuts, settings, and sign-ins.
#>
param([switch] $RemoveApps)
$ErrorActionPreference = 'Stop'
$target = Join-Path $env:LOCALAPPDATA 'Programs\Web App Wrap'
$exe = Join-Path $target 'WebAppWrap.exe'
$programs = [Environment]::GetFolderPath('Programs')

if ($RemoveApps) {
    # Wrapped apps are shortcuts that run WebAppWrap.exe with "--app <id>".
    $shell = New-Object -ComObject WScript.Shell
    $folders = @($programs, [Environment]::GetFolderPath('Desktop'))
    Get-ChildItem -Path $folders -Filter *.lnk -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $link = $shell.CreateShortcut($_.FullName)
        if ($link.TargetPath -eq $exe -and $link.Arguments -like '--app *') {
            Remove-Item $_.FullName
            Write-Host "Removed $($_.FullName)"
        }
    }
    $data = Join-Path $env:LOCALAPPDATA 'Web App Wrap'
    if (Test-Path $data) { Remove-Item -Recurse -Force $data }
}

Remove-Item -Force (Join-Path $programs 'Web App Wrap.lnk') -ErrorAction SilentlyContinue
if (Test-Path $target) { Remove-Item -Recurse -Force $target }
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
[Environment]::SetEnvironmentVariable('Path', (($userPath -split ';') | Where-Object { $_ -and $_ -ne $target }) -join ';', 'User')
Write-Host 'Web App Wrap was removed.'
