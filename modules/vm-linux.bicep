// ---------------------------------------------------------------------------
// modules/vm-linux.bicep
// Reusable Linux VM. NO public IP - reached only via Bastion Developer (SSH).
// Uses cloud-init (customData) rather than a CSE, which is the idiomatic
// Azure Linux pattern. NOT domain-joined - both the standalone endpoint and
// the attack box are deliberately kept out of AD to avoid dragging SSSD/
// Kerberos complexity into a Linux box for limited benefit in a lab.
// ---------------------------------------------------------------------------

param name string
param location string
param vmSize string
param subnetId string
param adminUsername string
@secure()
param adminPassword string
param imageReference object
param marketplacePlan object = {}
param cloudInit string = ''
param autoShutdownTime string
param timeZoneId string
param tags object

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${name}-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: name
  location: location
  tags: tags
  plan: empty(marketplacePlan) ? null : marketplacePlan
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: name
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: empty(cloudInit) ? null : base64(cloudInit)
    }
    storageProfile: {
      imageReference: imageReference
      osDisk: {
        name: '${name}-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${name}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: timeZoneId
    targetResourceId: vm.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

output vmName string = vm.name
output privateIpUsed string = nic.properties.ipConfigurations[0].properties.privateIPAddress
