// ---------------------------------------------------------------------------
// modules/vm-windows.bicep
// Reusable Windows VM. NO public IP - reached only via Bastion Developer.
// OS disk is Standard_LRS (Standard HDD) to minimise standing cost.
// Bootstrap (domain promotion / join) is optional and runs via the Custom
// Script Extension. Everything else (MDE, Sysmon, CA, honeytoken, file
// share/honeyfile) is a manual first-login step - see scripts/ and README.
// This keeps the CSE chain short and avoids fragile multi-step reboot races.
// ---------------------------------------------------------------------------

param name string
param location string
param vmSize string
param subnetId string
param privateIp string = ''
param dnsServers array = []
param adminUsername string
@secure()
param adminPassword string
param imageReference object
param scriptFileUri string = ''
@secure()
param scriptCommand string = ''
param autoShutdownTime string
param timeZoneId string
param tags object

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${name}-nic'
  location: location
  tags: tags
  properties: {
    dnsSettings: empty(dnsServers) ? null : {
      dnsServers: dnsServers
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: empty(privateIp) ? 'Dynamic' : 'Static'
          privateIPAddress: empty(privateIp) ? null : privateIp
          // No publicIPAddress - Bastion Developer provides all access
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: name
      adminUsername: adminUsername
      adminPassword: adminPassword
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

resource bootstrap 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (!empty(scriptFileUri)) {
  parent: vm
  name: 'bootstrap'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        scriptFileUri
      ]
    }
    protectedSettings: {
      commandToExecute: scriptCommand
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
