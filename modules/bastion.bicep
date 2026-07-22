// ---------------------------------------------------------------------------
// modules/bastion.bicep
// Azure Bastion Developer SKU. Free, shared infrastructure, no dedicated
// AzureBastionSubnet and no public IP required (unlike Basic/Standard/
// Premium). Supports ONE connection at a time - fine for solo use.
// ENV-SPECIFIC: Developer SKU is region-restricted. Verify availability for
// your chosen region before deploying:
//   az network bastion list-skus  (or check current docs - coverage expands over time)
// If unavailable in westeurope, -- is a reasonable fallback.
// ---------------------------------------------------------------------------

param location string
param vnetId string
param tags object

resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: 'BAS-EPH'
  location: location
  tags: tags
  sku: {
    name: 'Developer'
  }
  properties: {
    virtualNetwork: {
      id: vnetId
    }
  }
}
