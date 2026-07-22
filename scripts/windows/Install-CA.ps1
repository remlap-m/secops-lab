<#
    Install-CA.ps1  -  run ONCE on CA01, manually, AFTER the domain
    join (via Join-Domain.ps1) has completed and the VM has rebooted as a
    domain member. Run this via Bastion RDP, logged in as a domain admin.

    Installs AD Certificate Services as an Enterprise Root CA. Deliberately
    kept off the DC (separate box = more realistic architecture, and avoids
    the common CA-on-DC anti-pattern this lab is partly meant to teach you
    to spot). This gives you a genuine ESC1-ESC8 misconfiguration playground
    once you start tweaking certificate templates.

    Idempotent-ish: if AD CS is already configured, Install-AdcsCertification-
    Authority will report it and this script's try/catch just logs and exits.
#>
param(
    [string] $CAName = 'EPH-CA01-CA'
)

$ErrorActionPreference = 'Stop'

$cs = Get-WmiObject Win32_ComputerSystem
if (-not $cs.PartOfDomain) {
    throw "This VM is not domain-joined yet. Run Join-Domain.ps1 first and let it reboot before installing the CA role."
}

Write-Host "Installing AD-Certificate-Services role..."
Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools | Out-Null

Import-Module ADCSDeployment

try {
    Write-Host "Configuring Enterprise Root CA '$CAName'..."
    Install-AdcsCertificationAuthority `
        -CAType EnterpriseRootCA `
        -CACommonName $CAName `
        -KeyLength 2048 `
        -HashAlgorithmName SHA256 `
        -ValidityPeriod Years `
        -ValidityPeriodUnits 5 `
        -Force

    Write-Host "CA configured. Verify with: certutil -CAInfo"
}
catch {
    Write-Host "CA setup reported: $($_.Exception.Message)"
    Write-Host "If this says the CA is already configured, no action needed."
}
