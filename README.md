# On-prem SecOps lab (`eph.internal`)

Cheap, disposable AD lab for Sentinel/Defender practice. This repo contains
**only the ephemeral on-prem estate**. Two things live deliberately outside
it - see "What's NOT in this repo" below.

## Folder structure

This is exactly how the repo should look after upload. If any of this is
flattened or nested an extra level deep (a common drag-and-drop mistake),
`main.bicep`'s relative module references will fail immediately on deploy.

```
secops-lab/
├── README.md
├── PERMANENT-TIER.md
├── main.bicep
├── main.bicepparam
├── .gitignore
├── modules/
│   ├── network.bicep
│   ├── bastion.bicep
│   ├── vm-windows.bicep
│   └── vm-linux.bicep
├── scripts/
│   ├── windows/
│   │   ├── Setup-DomainController.ps1
│   │   ├── Join-Domain.ps1
│   │   ├── Onboard-MDE.ps1
│   │   ├── Install-Sysmon.ps1
│   │   ├── Install-CA.ps1
│   │   ├── New-HoneytokenAccount.ps1
│   │   └── Setup-FileShare.ps1
│   └── linux/
│       ├── cloud-init-endpoint.yaml
│       └── Onboard-MDE-Linux.sh
└── .github/
    └── workflows/
        ├── deploy.yml
        ├── destroy.yml
        └── power.yml
```

## Roster

- Domain controller (`VM-EPH-DC01`)
- Certificate Authority (`VM-EPH-CA01`, separate box - CA-on-DC is an
  anti-pattern this lab is partly meant to help you recognise)
- File server (`VM-EPH-FS01`) with a seeded share + honeyfile
- 4x Windows 11 clients (`VM-EPH-CL01..CL04`) - enough for real lateral
  movement scenarios
- Jump box (`VM-EPH-JMP01`) - convenience only, not a security boundary
- Standalone Linux endpoint (`VM-EPH-LNX01`) - not domain-joined
- Internal-only attack box (`VM-EPH-ATK01`, Kali) - your red-team platform

**No VM has a public IP.** Access is via **Azure Bastion Developer SKU**
(free, one connection at a time) through the Azure portal. There is no
inbound internet path to any VM at any point.

## What's NOT in this repo

- **The persistent tier** (`mini.internal`, Entra Connect,
  plus one Entra-joined client for Intune). Built manually, once, via Cloud
  Shell/RDP - never as Bicep, never wired into any workflow. Commands are
  recorded in `PERMANENT-TIER.md` for your own reference only; that file is
  documentation, not automation, and nothing in this repo calls it.
  Deallocate between uses; never run the destroy workflow anywhere near it;
  decommission Entra Connect properly (its uninstaller's deprovisioning
  option) before ever deleting `VM-MINI-DC01`.
- **Your Sentinel core** (workspace, analytics rules, Defender connector) -
  built once, separately, permanent, untouched by anything here.

## Order of operations

### Step 0 - one-time setup

1. Confirm your Visual Studio Azure credit is active.
2. Push this repo to your own GitHub (personal account is fine - no
   secrets live in these files).
3. Wire up OIDC (passwordless GitHub -> Azure):
   ```bash
   appId=$(az ad app create --display-name "secops-lab-deployer" --query appId -o tsv)
   az ad sp create --id "$appId"
   az ad app federated-credential create --id "$appId" --parameters '{
     "name": "github-main",
     "issuer": "https://token.actions.githubusercontent.com",
     "subject": "repo:<you>/secops-lab:ref:refs/heads/main",
     "audiences": ["api://AzureADTokenExchange"]
   }'
   ```
   **Scope the role to this lab's RG only** - not the whole subscription:
   ```bash
   subId=$(az account show --query id -o tsv)
   az group create --name RG-INFRA-LAB-EPHEMERAL --location westeurope
   az role assignment create --assignee "$appId" --role Contributor \
     --scope "/subscriptions/$subId/resourceGroups/RG-INFRA-LAB-EPHEMERAL"
   ```
4. Add GitHub secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
   `AZURE_SUBSCRIPTION_ID`, `LAB_ADMIN_PASSWORD`, `LAB_SAFEMODE_PASSWORD`.
5. Edit `main.bicepparam`: set `scriptBaseUri` to your repo's raw URL.
6. Verify Bastion Developer SKU is available in `westeurope` 
   and that your subscription has accepted Marketplace terms
   for the Kali image:
   ```bash
   az vm image terms accept --publisher kali-linux --offer kali --plan kali-2026-2
   ```

### Step 1 - the repeating loop

1. **Deploy** - Actions -> *Deploy on-prem lab* -> Run. DC promotes +
   reboots, then CA/file server/clients retry-join (up to ~30 min first
   time). Re-run the workflow if a VM didn't join - everything is
   idempotent.
2. **First-login checklist**, per VM, once, via Bastion (portal -> VM ->
   Connect -> Bastion):
   - Every Windows VM: `Onboard-MDE.ps1`, then `Install-Sysmon.ps1`.
   - `VM-EPH-DC01` only: `New-HoneytokenAccount.ps1` (ideally after
     seeding the domain with BadBlood so it blends in).
   - `VM-EPH-CA01` only: `Install-CA.ps1`.
   - `VM-EPH-FS01` only: `Setup-FileShare.ps1`.
   - `VM-EPH-LNX01`: `Onboard-MDE-Linux.sh` (download the tenant package
     from the Defender portal first).
3. **Generate signal** - BadBlood on the DC, Atomic Red Team on endpoints,
   Impacket/BloodHound from the attack box against the rest of the estate.
4. **Investigate** in Sentinel/Defender.
5. **End the session**: Actions -> *Power on-prem lab VMs* -> `deallocate`
   (fast resume, small standing disk cost) or *Destroy on-prem lab* (full
   reset, types `DESTROY` to confirm).

## Honeytoken / honeyfile detections

- **Account**: after running `New-HoneytokenAccount.ps1`, flag it in
  Defender portal -> Settings -> Identities -> Honeytoken. Any sign-in
  attempt fires automatically - no rule needed.
- **File**: after `Setup-FileShare.ps1`, add a Sentinel analytics rule:
  ```kql
  DeviceFileEvents
  | where FolderPath has "Passwords_Admin_Backup"
  | where ActionType in ("FileCreated", "FileModified", "FileRenamed")
  ```
  Tune the `ActionType` filter once you see what MDE actually reports for
  read/copy vs open on your file server.

## Cost model (approximate, West Europe - verify in the pricing calculator)

- Compute: burst sessions ≈ **£5-8/mo** across the full 9-VM roster at
  short session lengths.
- Disks (Standard HDD, billed even when deallocated) ≈ **£15-20/mo** for
  nine small OS disks.
- Public IPs: **£0** - none exist.
- Bastion Developer: **£0**.
- Ingestion: near zero on the Defender XDR free path.
- **Total ≈ £20-30/mo**, inside £40, leaving headroom for the permanent
  DC's own small standing disk cost (~£3-5/mo) elsewhere.

## The one finicky seam

AD promotion + domain join across separate VMs has an inherent timing
dependency, handled via fixed DC IP + member DNS pointed at the DC + a
30-minute retry loop in `Join-Domain.ps1`. If it still fails, just re-run
the deploy workflow - everything here is idempotent.
