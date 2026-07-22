<#
    Setup-FileShare.ps1  -  run ONCE on VM-EPH-DC01, manually, AFTER the
    domain join has completed and rebooted.

    Creates a shared folder with some plausible seed documents, plus a
    honeyfile: a file no legitimate process should ever touch. Pair this with
    a Sentinel analytics rule watching DeviceFileEvents for any read/copy of
    the honeyfile's path - see README for the KQL. Same principle as the
    honeytoken account, applied to data instead of credentials: a ransomware/
    exfil scenario against this share should trip it.
#>
$ErrorActionPreference = 'Stop'

$shareRoot = 'C:\Shares\Finance'
New-Item -ItemType Directory -Path $shareRoot -Force | Out-Null

# A few plausible, boring seed files so the share doesn't look empty/staged.
'Q1 2026 budget summary - draft' | Out-File "$shareRoot\Q1_Budget_Draft.txt"
'Vendor contact list' | Out-File "$shareRoot\Vendor_Contacts.txt"

# The honeyfile - a plausible-looking, high-value-sounding target.
'This file should never be opened by a legitimate process.' | Out-File "$shareRoot\Passwords_Admin_Backup.xlsx.txt"

New-SmbShare -Name 'Finance' -Path $shareRoot -FullAccess 'Everyone' -ErrorAction SilentlyContinue | Out-Null

Write-Host "Share 'Finance' created at $shareRoot."
Write-Host "Honeyfile: $shareRoot\Passwords_Admin_Backup.xlsx.txt"
Write-Host "Next: create a Sentinel analytics rule on DeviceFileEvents where FolderPath contains 'Passwords_Admin_Backup' - see README."
