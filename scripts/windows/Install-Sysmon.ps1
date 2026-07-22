<#
    Install-Sysmon.ps1  -  run ONCE per Windows VM, manually, after first login.

    Installs Sysinternals Sysmon with a well-known community config (SwiftOnSecurity's
    baseline). Sysmon's process-tree, named-pipe, and registry telemetry is what most
    public Sentinel hunting queries and detection content assume you have - default
    Defender/AMA telemetry alone is not enough for a lot of published KQL content.

    Requires internet access from the VM (downloads ~2 small files from GitHub/
    live.sysinternals.com). Run this AFTER domain join / MDE onboarding.
#>
$ErrorActionPreference = 'Stop'

$work = 'C:\lab-tools\sysmon'
New-Item -ItemType Directory -Path $work -Force | Out-Null

Write-Host "Downloading Sysmon..."
Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/Sysmon.zip' -OutFile "$work\Sysmon.zip"
Expand-Archive -Path "$work\Sysmon.zip" -DestinationPath $work -Force

Write-Host "Downloading SwiftOnSecurity baseline config..."
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml' -OutFile "$work\sysmonconfig.xml"

Write-Host "Installing Sysmon64 with baseline config..."
& "$work\Sysmon64.exe" -accepteula -i "$work\sysmonconfig.xml"

Write-Host "Sysmon installed. Verify with: Get-Service Sysmon64"
