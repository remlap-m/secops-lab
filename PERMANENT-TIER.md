# Permanent manual tier

This file documents the permanent mini lab for your own record.
It is **not** Bicep, is **not** called by any workflow, and should **never**
be wired into this repo's pipeline. Keeping it out of automation entirely is
deliberate: this tier is stateful (Entra Connect sync state, Intune
enrollment) and does not tolerate being rebuilt or destroyed the way the
disposable `eph.internal` estate does. See README.md for the reasoning.

Run these commands by hand, once, in Azure Cloud Shell. Deallocate the VMs
between uses; never destroy this resource group casually; decommission Entra
Connect properly (its uninstaller's deprovisioning option) before ever
deleting `VM-MINI-DC01`.

## 1. Resource group, network, Bastion

```bash
az group create --name RG-INFRA-LAB-MINI --location westeurope

az network vnet create \
  --resource-group RG-INFRA-LAB-MINI \
  --name VNET-MINI \
  --address-prefix 10.30.0.0/16 \
  --subnet-name SNET-DEFAULT \
  --subnet-prefix 10.30.1.0/24

az network bastion create \
  --resource-group RG-INFRA-LAB-MINI \
  --name BAS-MINI \
  --vnet-name VNET-MINI \
  --sku Developer \
  --location westeurope
```

## 1a. Restore outbound internet access (required - read before continuing)

Since March 31, 2026, Azure no longer grants default outbound internet access
to newly created VNets/subnets - they're private by default, and nothing on
them can reach the internet unless you explicitly enable an outbound method
(NAT Gateway, public IP, load balancer outbound rules). This is a genuine,
permanent Azure platform change, not specific to this lab - every VNet built
with `az network vnet create` from here on will hit this.

A NAT Gateway (Microsoft's recommended fix) is a standing resource with its
own continuous hourly charge (~£25-30/month) even when idle - disproportionate
for a lab. Instead, use Microsoft's documented free opt-out, which restores
the old default-allow behavior on just this subnet, at no ongoing cost:

```bash
az network vnet subnet update \
  --resource-group RG-INFRA-LAB-MINI \
  --vnet-name VNET-MINI \
  --name SNET-DEFAULT \
  --default-outbound-access true
```

If that exact flag errors, run `az network vnet subnet update --help` and look
for whichever current parameter name refers to default outbound access - the
flag name has shifted before and may again.

Without this step, `VM-MINI-DC01` and `VM-MINI-CL01` will build successfully but
have NO internet at all - no Windows Update, no MDE onboarding, nothing. Do
this before building either VM, not after.

## 2.  DC (`mini.internal`)

Default OS disk size (127 GB - marketplace images cannot be shrunk below their native size; S10 tier, ~£4-5/month standing), no public IP.

```bash
az vm create \
  --resource-group RG-INFRA-LAB-MINI \
  --name VM-MINI-DC01 \
  --image MicrosoftWindowsServer:WindowsServer:2022-datacenter-g2:latest \
  --size Standard_B2s_v2 \
  --vnet-name VNET-MINI \
  --subnet SNET-DEFAULT \
  --public-ip-address "" \
  --admin-username labadmin \
  --admin-password 'ChooseAStrongPassword1!'

az vm auto-shutdown --resource-group RG-INFRA-LAB-MINI --name VM-MINI-DC01 --time 1900
```

Verify the image SKU is still current before running:
`az vm image list --publisher MicrosoftWindowsServer --offer WindowsServer --all -o table`

## 3. Domain-joined client (`VM-MINI-CL01`)

Default OS disk size (image minimum - check per-image with `az vm image show --query osDiskImage.sizeInGb`), Trusted Launch + vTPM enabled now so Autopilot stays an option
later without a rebuild.

```bash
az vm create \
  --resource-group RG-INFRA-LAB-MINI \
  --name VM-MINI-CL01 \
  --image MicrosoftWindowsDesktop:windows-11:win11-24h2-ent:latest \
  --size Standard_B2s_v2 \
  --vnet-name VNET-MINI \
  --subnet SNET-DEFAULT \
  --public-ip-address "" \
  --security-type TrustedLaunch \
  --enable-secure-boot true \
  --enable-vtpm true \
  --admin-username labadmin \
  --admin-password 'ChooseAnotherStrongPassword2!'

az vm auto-shutdown --resource-group RG-INFRA-LAB-MINI --name VM-MINI-CL01 --time 1900
```

## 3a. Point the client's DNS at the DC (required before domain join)

`VM-MINI-CL01` will not resolve `mini.internal` until its NIC is explicitly
told where the DC's DNS server is - this is never set automatically. Do this
AFTER the DC has been promoted (Step 4's first part, below), since the DC
only becomes an authoritative DNS server once `-InstallDns` has run.

Find the DC's actual private IP (no static IP was set at creation, so it's
whatever Azure assigned):
```bash
az vm list-ip-addresses -g RG-INFRA-LAB-MINI -n VM-MINI-DC01 -o table
```

Find the client's NIC name (Azure auto-generates this; don't assume the
exact string):
```bash
az vm show -g RG-INFRA-LAB-MINI -n VM-MINI-CL01 --query "networkProfile.networkInterfaces[0].id" -o tsv
```
That returns a full resource ID - the NIC name is the last segment after the
final `/`.

Point the client's DNS at the DC's IP from above:
```bash
az network nic update -g RG-INFRA-LAB-MINI -n <nic-name-from-above> --dns-servers <DC-private-IP-from-above>
```

Reboot the client to force it to pick up the change immediately, rather than
waiting on its next DHCP renewal:
```bash
az vm restart -g RG-INFRA-LAB-MINI -n VM-MINI-CL01
```

## 4. Manual post-deploy steps (via Bastion RDP - not scripted)

**Promote the DC** - RDP into `VM-MINI-DC01` via Bastion, PowerShell as admin:

```powershell
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
Install-ADDSForest `
  -DomainName "mini.internal" `
  -DomainNetbiosName "MINI" `
  -InstallDns `
  -Force
```
Prompts interactively for a DSRM password; reboots itself.

**Install Entra Connect (If wishing to test Hybrid scenarios)** - download interactively from
`https://aka.ms/AADConnectSyncFullPackage` (GUI installer by design, no
scriptable path) and run on `VM-MINI-DC01` after it reboots.

**Confirm Entra Connect is syncing devices, not just users** - not always on
by default depending on which options were selected in the wizard. On
`VM-MINI-DC01`, reopen the Entra Connect configuration wizard and check
"Configure device options" has device sync enabled before continuing.

**Domain-join the client the normal way** - RDP into `VM-MINI-CL01` ->
Settings -> System -> About -> "Rename this PC (advanced)" -> Domain ->
join `mini.internal` with the DC's local admin credentials. Reboot when
prompted.

**Force the hybrid-join sync**, rather than waiting on its own schedule -
elevated PowerShell on `VM-MINI-CL01`:
```powershell
Start-ScheduledTask -TaskPath "\Microsoft\Windows\Workplace Join\" -TaskName "Automatic-Device-Join"
```

**Verify genuine hybrid join** - on `VM-MINI-CL01`:
```
dsregcmd /status
```
Look for **both** `AzureAdJoined: YES` and `DomainJoined: YES` together -
either alone means the join is incomplete. Triggers Intune auto-enrollment
if the tenant's MDM user scope (Intune admin center -> Devices -> Enrollment
-> Windows) includes this device/user or "All".

## Cost

~£9-10/month standing (two default-size OS disks), regardless of use. Compute itself only
bills for the odd hour you're actually logged in.
