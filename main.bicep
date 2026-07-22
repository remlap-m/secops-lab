// ===========================================================================
// main.bicep  -  EPHEMERAL ON-PREM LAB  (domain: eph.internal)
// ===========================================================================
// Deploy into RG-INFRA-LAB-EPHEMERAL. Delete that RG to reset to zero cost.
//
// This repo deliberately contains ONLY the ephemeral estate. The permanent
// Persistent DC (mini.internal, Entra Connect) is built manually,
// once, outside this repo and outside this pipeline - see README. No file
// here references it, so no workflow can ever touch it, even by mistake.
//
// Roster: DC, CA, N Windows clients (default 4), file server, standalone
// Linux endpoint, internal-only attack box, jump box. NO public IPs anywhere
// - Azure Bastion Developer SKU (free) provides all RDP/SSH access.
//
// Bootstrap chain (Custom Script Extension, Windows only) does ONLY domain
// promotion / join - it is idempotent and retry-based. Everything else
// (Defender onboarding, Sysmon, CA role, honeytoken account, file share +
// honeyfile) is a short manual first-login checklist per VM - see README.
// This is deliberate: chaining reboot-dependent steps inside CSEs is fragile;
// a documented one-off checklist is more reliable and easier to reason about.
// ===========================================================================

targetScope = 'resourceGroup'

@description('Azure region. Verify Bastion Developer SKU availability here first.')
param location string = 'westeurope'

param vnetAddressPrefix string = '10.20.0.0/16'
param subnetPrefix string = '10.20.1.0/24'

@description('Fixed private IP for the DC so every other VM can resolve it.')
param dcPrivateIp string = '10.20.1.4'

@description('Ephemeral lab AD domain. Deliberately different from the separate mini.internal forest.')
param domainName string = 'eph.internal'
param netbiosName string = 'EPH'

param adminUsername string
@secure()
param adminPassword string
@secure()
param safeModePassword string

@description('Raw base URL of this repo\'s scripts/windows folder, e.g. https://raw.githubusercontent.com/<you>/sentinel-lab/main/scripts/windows')
param scriptBaseUri string

@description('Number of Windows client workstations to deploy.')
param clientCount int = 4

param dcVmSize string = 'Standard_B2s_v2'
param serverVmSize string = 'Standard_B2s_v2'
param clientVmSize string = 'Standard_B2s_v2'
param linuxVmSize string = 'Standard_B2ts_v2'

param autoShutdownTime string = '1900'
param timeZoneId string = 'GMT Standard Time'

var tags = {
  env: 'lab'
  domain: 'eph.internal'
  tier: 'ephemeral-compute'
  autoDelete: 'true'
}

// ENV-SPECIFIC: verify current SKUs before first deploy -
//   az vm image list --publisher MicrosoftWindowsServer --offer WindowsServer --all -o table
//   az vm image list --publisher MicrosoftWindowsDesktop --offer windows-11 --all -o table
var serverImage = {
  publisher: 'MicrosoftWindowsServer'
  offer: 'WindowsServer'
  sku: '2022-datacenter-g2'
  version: 'latest'
}
var clientImage = {
  publisher: 'MicrosoftWindowsDesktop'
  offer: 'windows-11'
  sku: 'win11-24h2-ent'
  version: 'latest'
}
// Ubuntu for the standalone endpoint.
var linuxImage = {
  publisher: 'Canonical'
  offer: '0001-com-ubuntu-server-jammy'
  sku: '22_04-lts-gen2'
  version: 'latest'
}
// Kali for the internal-only attack box. ENV-SPECIFIC: confirm current offer/sku -
//   az vm image list --publisher kali-linux --all -o table
// and that your subscription has accepted Marketplace terms for it
//   (az vm image terms accept --publisher kali-linux --offer kali --plan <sku>).
var attackBoxImage = {
  publisher: 'kali-linux'
  offer: 'kali'
  sku: 'kali-2026-2'
  version: 'latest'
}
// Marketplace-plan images (like Kali) require this alongside imageReference,
// separate from having accepted the terms via `az vm image terms accept`.
// Values must match imageReference exactly (Azure's 'plan' naming differs
// slightly: name=sku, product=offer).
var attackBoxPlan = {
  name: attackBoxImage.sku
  publisher: attackBoxImage.publisher
  product: attackBoxImage.offer
}

var dcCommand = 'powershell -ExecutionPolicy Bypass -File Setup-DomainController.ps1 -DomainName "${domainName}" -NetbiosName "${netbiosName}" -SafeModePassword "${safeModePassword}"'
var joinCommand = 'powershell -ExecutionPolicy Bypass -File Join-Domain.ps1 -DomainName "${domainName}" -DomainAdminUser "${netbiosName}\\${adminUsername}" -DomainAdminPassword "${adminPassword}"'

// ---------------------------------------------------------------------------
// NETWORK + ACCESS
// ---------------------------------------------------------------------------

module network 'modules/network.bicep' = {
  name: 'deploy-network'
  params: {
    location: location
    vnetAddressPrefix: vnetAddressPrefix
    subnetPrefix: subnetPrefix
    tags: tags
  }
}

module bastion 'modules/bastion.bicep' = {
  name: 'deploy-bastion'
  params: {
    location: location
    vnetId: network.outputs.vnetId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// DOMAIN CONTROLLER - DNS left on Azure-provided so it can reach the repo
// before it becomes the domain's own DNS server.
// ---------------------------------------------------------------------------

module dc 'modules/vm-windows.bicep' = {
  name: 'deploy-dc'
  params: {
    name: 'vm-eph-dc01'
    location: location
    vmSize: dcVmSize
    subnetId: network.outputs.subnetId
    privateIp: dcPrivateIp
    dnsServers: []
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageReference: serverImage
    scriptFileUri: '${scriptBaseUri}/Setup-DomainController.ps1'
    scriptCommand: dcCommand
    autoShutdownTime: autoShutdownTime
    timeZoneId: timeZoneId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// CERTIFICATE AUTHORITY - domain-joined by CSE; CA role install is a manual
// first-login step (Install-CA.ps1) to avoid racing the join reboot.
// ---------------------------------------------------------------------------

module ca 'modules/vm-windows.bicep' = {
  name: 'deploy-ca'
  dependsOn: [dc]
  params: {
    name: 'vm-eph-ca01'
    location: location
    vmSize: serverVmSize
    subnetId: network.outputs.subnetId
    dnsServers: [dcPrivateIp]
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageReference: serverImage
    scriptFileUri: '${scriptBaseUri}/Join-Domain.ps1'
    scriptCommand: joinCommand
    autoShutdownTime: autoShutdownTime
    timeZoneId: timeZoneId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// FILE SERVER - domain-joined; share + honeyfile set up manually post-join
// (Setup-FileShare.ps1).
// ---------------------------------------------------------------------------

module fileServer 'modules/vm-windows.bicep' = {
  name: 'deploy-fileserver'
  dependsOn: [dc]
  params: {
    name: 'vm-eph-fs01'
    location: location
    vmSize: serverVmSize
    subnetId: network.outputs.subnetId
    dnsServers: [dcPrivateIp]
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageReference: serverImage
    scriptFileUri: '${scriptBaseUri}/Join-Domain.ps1'
    scriptCommand: joinCommand
    autoShutdownTime: autoShutdownTime
    timeZoneId: timeZoneId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// WINDOWS CLIENTS - looped, default 4.
// ---------------------------------------------------------------------------

module clients 'modules/vm-windows.bicep' = [for i in range(0, clientCount): {
  name: 'deploy-client-${i + 1}'
  dependsOn: [dc]
  params: {
    name: 'vm-eph-win11-${i + 1}'
    location: location
    vmSize: clientVmSize
    subnetId: network.outputs.subnetId
    dnsServers: [dcPrivateIp]
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageReference: clientImage
    scriptFileUri: '${scriptBaseUri}/Join-Domain.ps1'
    scriptCommand: joinCommand
    autoShutdownTime: autoShutdownTime
    timeZoneId: timeZoneId
    tags: tags
  }
}]

// ---------------------------------------------------------------------------
// JUMP BOX - workflow convenience only now (Bastion removed the security
// reason for it). Not domain-joined; kept as a clean "start here" box.
// ---------------------------------------------------------------------------

module jumpBox 'modules/vm-windows.bicep' = {
  name: 'deploy-jumpbox'
  dependsOn: [dc]
  params: {
    name: 'vm-eph-jump01'
    location: location
    vmSize: clientVmSize
    subnetId: network.outputs.subnetId
    dnsServers: [dcPrivateIp]
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageReference: clientImage
    autoShutdownTime: autoShutdownTime
    timeZoneId: timeZoneId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// STANDALONE LINUX ENDPOINT - not domain-joined. Basic cloud-init only;
// MDE-for-Linux onboarding is a manual first-login step (tenant-specific).
// ---------------------------------------------------------------------------

module linuxEndpoint 'modules/vm-linux.bicep' = {
  name: 'deploy-linux-endpoint'
  dependsOn: [dc]
  params: {
    name: 'vm-eph-lnx01'
    location: location
    vmSize: linuxVmSize
    subnetId: network.outputs.subnetId
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageReference: linuxImage
    cloudInit: loadTextContent('scripts/linux/cloud-init-endpoint.yaml')
    autoShutdownTime: autoShutdownTime
    timeZoneId: timeZoneId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// ATTACK BOX - internal-only, Kali. Idle most of a session; used deliberately
// to generate real attacker telemetry against the rest of the estate.
// ---------------------------------------------------------------------------

module attackBox 'modules/vm-linux.bicep' = {
  dependsOn: [dc]
  name: 'deploy-attackbox'
  params: {
    name: 'vm-eph-atk01'
    location: location
    vmSize: linuxVmSize
    subnetId: network.outputs.subnetId
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageReference: attackBoxImage
    marketplacePlan: attackBoxPlan
    autoShutdownTime: autoShutdownTime
    timeZoneId: timeZoneId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// OUTPUTS
// ---------------------------------------------------------------------------

output domainController string = dc.outputs.vmName
output dcPrivateIp string = dc.outputs.privateIpUsed
output certificateAuthority string = ca.outputs.vmName
output fileServer string = fileServer.outputs.vmName
output jumpBox string = jumpBox.outputs.vmName
output linuxEndpoint string = linuxEndpoint.outputs.vmName
output attackBox string = attackBox.outputs.vmName
