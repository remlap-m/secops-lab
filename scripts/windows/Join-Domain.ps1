<#
    Join-Domain.ps1
    Runs on the CA, file server, and every client via the Custom Script
    Extension. The DC may still be promoting when this starts, so we RETRY:
    wait for the domain to resolve, then Add-Computer -Restart. Tolerant of
    the DC/member timing race without external orchestration.
    Idempotent: already joined? Exits cleanly.
    Logs to C:\lab-join.log.
#>
param(
    [Parameter(Mandatory = $true)] [string] $DomainName,
    [Parameter(Mandatory = $true)] [string] $DomainAdminUser,
    [Parameter(Mandatory = $true)] [string] $DomainAdminPassword
)

$ErrorActionPreference = 'Stop'
$log = 'C:\lab-join.log'
function Log($m) { "$([DateTime]::UtcNow.ToString('s'))Z  $m" | Tee-Object -FilePath $log -Append }

try {
    $cs = Get-WmiObject Win32_ComputerSystem
    if ($cs.PartOfDomain -and $cs.Domain -ieq $DomainName) {
        Log "Already joined to '$DomainName'. Exiting."
        return
    }

    $securePwd = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($DomainAdminUser, $securePwd)

    $maxAttempts = 30
    $delaySeconds = 60

    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            Log "Attempt $i/$maxAttempts : testing domain reachability."
            Resolve-DnsName -Name $DomainName -ErrorAction Stop | Out-Null

            Log "Domain resolves. Attempting join."
            Add-Computer -DomainName $DomainName -Credential $cred -Force -Restart
            Log "Join succeeded. Rebooting."
            return
        }
        catch {
            Log "Not ready yet: $($_.Exception.Message)"
            Start-Sleep -Seconds $delaySeconds
        }
    }

    throw "Domain join failed after $maxAttempts attempts. Confirm the DC promoted, then re-run the deploy workflow."
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    throw
}
