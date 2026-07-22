// ---------------------------------------------------------------------------
// modules/network.bicep
// VNet + single subnet + NSG. No public IPs are created anywhere in this repo
// - Azure Bastion Developer SKU provides all remote access, so there is no
// inbound internet path to guard. The NSG here is defence-in-depth only:
// Azure's default rules already deny all inbound internet traffic and allow
// intra-VNet traffic: we add nothing beyond that, deliberately.
// ---------------------------------------------------------------------------

param location string
param vnetAddressPrefix string
param subnetPrefix string
param tags object

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'NSG-EPH'
  location: location
  tags: tags
  properties: {
    securityRules: [] // Azure default rules (deny internet inbound, allow VNet) are sufficient here
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'VNET-EPH'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'SNET-EPH-DEFAULT'
        properties: {
          addressPrefix: subnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output subnetId string = vnet.properties.subnets[0].id
