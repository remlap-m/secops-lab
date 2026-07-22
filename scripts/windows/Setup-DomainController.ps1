<#
    Setup-DomainController.ps1
    Runs on VM-EPH-DC01 via the Custom Script Extension.
    Installs AD DS and promotes this VM into a new forest. Install-ADDSForest
    triggers an automatic reboot - the CSE reporting "done" at that point is
    expected, not a failure.
    Idempotent: already a DC? Exits cleanly.
    Logs to C:\lab-dc-setup.log.
#>
param(
    [Parameter(Mandatory = $true)] [string] $DomainName,
    [Parameter(Mandatory = $true)] [string] $NetbiosName,
    [Parameter(Mandatory = $true)] [string] $SafeModePassword
)

$ErrorActionPreference = 'Stop'
$log = 'C:\lab-dc-setup.log'
function Log($m) { "$([DateTime]::UtcNow.ToString('s'))Z  $m" | Tee-Object -FilePath $log -Append }

try {
    Log "Starting DC setup for domain '$DomainName'."

    $role = (Get-WmiObject Win32_ComputerSystem).DomainRole
    if ($role -ge 4) {
        Log "Already a domain controller (DomainRole=$role). Exiting."
        return
    }

    Log "Installing AD-Domain-Services role."
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

    Import-Module ADDSDeployment
    $securePwd = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

    Log "Promoting to new forest. Auto-reboot will follow."
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $NetbiosName `
        -SafeModeAdministratorPassword $securePwd `
        -InstallDns `
        -ForestMode 'WinThreshold' `
        -DomainMode 'WinThreshold' `
        -NoRebootOnCompletion:$false `
        -Force

    Log "Install-ADDSForest returned - reboot imminent."
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    throw
}
