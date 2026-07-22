<#
    New-HoneytokenAccount.ps1  -  run ONCE on VM-EPH-DC01, manually, after the
    DC has promoted and (ideally) after BadBlood has seeded the domain with
    thousands of realistic decoy objects.

    Creates a plausible-looking AD user that should NEVER legitimately
    authenticate. After running this, flag the account as a honeytoken in the
    Defender portal (Settings -> Identities -> Honeytoken). From then on, ANY
    sign-in attempt against it - successful or failed - fires a high-severity,
    zero-tuning alert, because there is no legitimate baseline to distinguish
    it from. The value comes from the account being indistinguishable from a
    real one to an attacker running BloodHound/Kerberoasting against the
    domain - hence seeding it AFTER BadBlood, so it blends in.

    Password is randomised and discarded - nobody is meant to log in with it.
#>
param(
    [string] $SamAccountName = 'svc-backup-legacy',
    [string] $OuPath = ''
)

$ErrorActionPreference = 'Stop'

Import-Module ActiveDirectory

$randomPassword = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$securePwd = ConvertTo-SecureString $randomPassword -AsPlainText -Force

$params = @{
    Name                 = $SamAccountName
    SamAccountName       = $SamAccountName
    AccountPassword      = $securePwd
    Enabled              = $true
    PasswordNeverExpires = $true
    Description          = 'Legacy backup service account - DO NOT USE'
}
if ($OuPath) { $params['Path'] = $OuPath }

New-ADUser @params

Write-Host "Honeytoken account '$SamAccountName' created."
Write-Host "Next: Defender portal -> Settings -> Identities -> Honeytoken -> add this account."
Write-Host "The random password above is deliberately not shown or saved - nobody should ever authenticate as this account."
