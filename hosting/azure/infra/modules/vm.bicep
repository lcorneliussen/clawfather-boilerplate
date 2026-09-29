// The gateway host: Ubuntu 24.04 (Gen2, Trusted Launch), cloud-init for first boot, and a
// separately managed data disk that survives the VM (deleteOption Detach + CanNotDelete lock).
param name string
param location string
param tags object
param vmSize string
param adminUsername string
param sshPublicKeys array

@description('User-assigned identity the VM (and so the gateway container, via IMDS) runs as')
param identityId string
param subnetId string
param publicIpId string
param dataDiskSizeGb int

@description('cloud-init user data (infra/cloud-init.yaml, placeholders already substituted)')
param cloudInit string

resource dataDisk 'Microsoft.Compute/disks@2023-10-02' = {
  name: 'disk-${name}-data'
  location: location
  tags: tags
  sku: { name: 'StandardSSD_LRS' }
  properties: {
    creationData: { createOption: 'Empty' }
    diskSizeGB: dataDiskSizeGb
  }
}

resource dataDiskLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: 'keep-claw-state'
  scope: dataDisk
  properties: {
    level: 'CanNotDelete'
    notes: 'Gateway state, workspaces and backups live on this disk. Remove the lock deliberately before deleting.'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-${name}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: subnetId }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIpId
            properties: { deleteOption: 'Detach' } // the address outlives the VM: DNS points at it
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: 'vm-${name}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identityId}': {} }
  }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        name: 'disk-${name}-os'
        createOption: 'FromImage'
        diskSizeGB: 32
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
        deleteOption: 'Delete'
      }
      dataDisks: [
        {
          lun: 0
          createOption: 'Attach'
          caching: 'None' // SQLite on the state volume: no host caching
          managedDisk: { id: dataDisk.id }
          deleteOption: 'Detach'
        }
      ]
    }
    osProfile: {
      computerName: 'vm-${name}'
      adminUsername: adminUsername
      customData: base64(cloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        patchSettings: { patchMode: 'ImageDefault' } // unattended-upgrades handles patching
        ssh: {
          publicKeys: [
            for key in sshPublicKeys: {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: key
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: { deleteOption: 'Delete' }
        }
      ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: { secureBootEnabled: true, vTpmEnabled: true }
    }
    diagnosticsProfile: {
      bootDiagnostics: { enabled: true }
    }
  }
}

output vmName string = vm.name
output adminUsername string = adminUsername
