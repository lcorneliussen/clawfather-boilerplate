// Network, perimeter and the static public IP. The IP exists from the foundation pass on,
// so the DNS record can be created before the VM. SSH is closed unless an operator CIDR is
// configured; the deploy workflow adds a temporary rule (priority 300-389, name
// ci-ssh-<run id>) for its runner and removes it afterwards. An apply of this module rewrites
// the rule set, so it also removes a CI rule that happens to be live at that moment.
param name string
param location string
param tags object
param sshSourceCidrs array
param dnsLabel string

var baseRules = [
  {
    name: 'allow-https'
    properties: {
      priority: 100
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourceAddressPrefix: 'Internet'
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '443'
    }
  }
  {
    name: 'allow-http-acme'
    properties: {
      priority: 110
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourceAddressPrefix: 'Internet'
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '80'
    }
  }
  {
    name: 'allow-http3'
    properties: {
      priority: 120
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Udp'
      sourceAddressPrefix: 'Internet'
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '443'
    }
  }
]

var sshRules = empty(sshSourceCidrs) ? [] : [
  {
    name: 'allow-ssh-operators'
    properties: {
      priority: 200
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourceAddressPrefixes: sshSourceCidrs
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '22'
    }
  }
]

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${name}'
  location: location
  tags: tags
  properties: {
    securityRules: concat(baseRules, sshRules)
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${name}'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: ['10.42.0.0/24'] }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.42.0.0/26'
          networkSecurityGroup: { id: nsg.id }
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-${name}'
  location: location
  tags: tags
  sku: { name: 'Standard', tier: 'Regional' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 30
    dnsSettings: { domainNameLabel: dnsLabel }
  }
}

output subnetId string = vnet.properties.subnets[0].id
output publicIpId string = publicIp.id
output publicIp string = publicIp.properties.ipAddress
output fqdn string = publicIp.properties.dnsSettings.fqdn
output nsgName string = nsg.name
