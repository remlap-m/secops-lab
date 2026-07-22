<#
    Onboard-MDE.ps1  -  run ONCE per Windows VM, manually, after first login.

    MDE onboarding uses a TENANT-SPECIFIC package only you can download - it
    cannot be baked into this repo.

    How to get it:
      Defender portal -> Settings -> Endpoints -> Onboarding.
      OS = Windows 10/11 or Windows Server. Deployment method = Local Script.
      Download the .zip, extract WindowsDefenderATPLocalOnboardingScript.cmd,
      copy it to the VM, then:
        powershell -ExecutionPolicy Bypass -File Onboard-MDE.ps1 -OnboardingCmd "C:\path\WindowsDefenderATPLocalOnboardingScript.cmd"

    Why manual, not baked into an image or CSE: onboarding cloned/imaged disks
    risks device-identity collisions in the Defender portal. One deliberate
    run per VM keeps device identities clean.

    Once onboarded, DeviceProcessEvents / DeviceNetworkEvents / IdentityLogon-
    Events etc. flow to Defender XDR, and into Sentinel at ZERO ingestion
    cost via the connector already configured in the core resource group.
#>
param(
    [Parameter(Mandatory = $true)] [string] $OnboardingCmd
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $OnboardingCmd)) {
    throw "Onboarding script not found at '$OnboardingCmd'. Download it from the Defender portal first (see header)."
}

Write-Host "Running MDE onboarding: $OnboardingCmd"
& cmd.exe /c "`"$OnboardingCmd`""
Write-Host "Onboarding invoked. Allow a few minutes, then confirm the device appears in Defender portal -> Assets -> Devices."
