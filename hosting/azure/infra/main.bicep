// Azure resources for one claw instance: a single VM running Docker Compose. Upstream-owned.
//
// One resource group per instance, deployed in two passes by hosting/azure/bootstrap.sh or
// the Infrastructure workflow:
//   deployVm = false   foundation: deploy + runtime identities, the two Key Vaults, container
//                      registry, network and the static public IP (so DNS can be set early)
//   deployVm = true    the VM, its locked data disk and NIC on top of the foundation
//
// Role assignments are written only by the operator pass (manageRoleAssignments = true).
// The pipeline identity holds Contributor on the group and may not assign roles.
targetScope = 'resourceGroup'

@description('Instance slug (CLAW_INSTANCE in instance/claw.env): names every resource and the host data root /srv/<instance>')
@minLength(2)
@maxLength(24)
param instance string

@description('Azure region; defaults to the resource group location')
param location string = resourceGroup().location

param tags object = {
  'claw-instance': instance
  'managed-by': 'bicep'
}

@description('GitHub repository in owner/name form whose Actions assume the deploy identity')
param githubRepository string

@description('Optional: the same repository in GitHub\'s id-qualified form (owner@ownerId/name@repoId). Some organisations issue OIDC subjects in this form; when set, both forms are registered. Ids: gh api repos/OWNER/REPO --jq \'.owner.id, .id\'')
param githubRepositoryWithIds string = ''

@description('GitHub environment bound to the federated credential')
param githubEnvironment string = 'production'

@description('Object id of the operator running the foundation pass; granted Key Vault Secrets Officer on both vaults. Empty in the pipeline.')
param deployerPrincipalId string = ''

@allowed(['User', 'ServicePrincipal', 'Group'])
param deployerPrincipalType string = 'User'

@description('Write role assignments (operator pass). The pipeline passes false.')
param manageRoleAssignments bool = true

@description('Deploy the VM and its data disk (second pass)')
param deployVm bool = false

@description('VM size. B2ms: 2 vCPU / 8 GiB — the gateway with a browser, Caddy and oauth2-proxy are mostly idle.')
param vmSize string = 'Standard_B2ms'

@description('Linux admin user and SSH deploy user. cloud-init restricts sshd to this user.')
param adminUsername string = 'deploy'

@description('SSH public keys authorised for the admin user: the CI deploy key plus operator keys')
param sshPublicKeys array = []

@description('CIDRs allowed to reach SSH permanently (operators). CI adds a temporary rule per run.')
param sshSourceCidrs array = []

var restrictedSshSourceCidrs = contains(sshSourceCidrs, '0.0.0.0/0') || contains(sshSourceCidrs, '::/0')
  ? fail('SSH source CIDRs must not include a world-open prefix')
  : sshSourceCidrs

@minValue(32)
param dataDiskSizeGb int = 64

var suffix = toLower(uniqueString(resourceGroup().id))
// Key Vault names are 3-24 characters: 'kv-' + 12 + '-rt-' + 5 = 24.
var vaultStem = take(instance, 12)

module identity './modules/identity.bicep' = {
  name: 'identity'
  params: {
    name: 'id-github-${instance}'
    clawName: 'id-claw-${instance}'
    location: location
    tags: tags
    githubRepository: githubRepository
    githubRepositoryWithIds: githubRepositoryWithIds
    githubEnvironment: githubEnvironment
    manageRoleAssignments: manageRoleAssignments
  }
}

// Deploy secrets: the CI SSH key pair and the OAuth client. Read by the GitHub deploy
// identity only; nothing the gateway can reach.
module keyVault './modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    name: 'kv-${vaultStem}-${take(suffix, 5)}'
    location: location
    tags: tags
    readerPrincipalIds: [identity.outputs.principalId]
    officerPrincipalId: deployerPrincipalId
    officerPrincipalType: deployerPrincipalType
    manageRoleAssignments: manageRoleAssignments
  }
}

// Secrets the *agent* may read at runtime (through the VM's user-assigned identity).
// Deliberately separate from the deploy vault above: whatever is in here is readable by
// every prompt the agent executes.
module runtimeVault './modules/keyvault.bicep' = {
  name: 'runtime-keyvault'
  params: {
    name: 'kv-${vaultStem}-rt-${take(suffix, 5)}'
    location: location
    tags: tags
    readerPrincipalIds: [identity.outputs.clawPrincipalId]
    officerPrincipalId: deployerPrincipalId
    officerPrincipalType: deployerPrincipalType
    manageRoleAssignments: manageRoleAssignments
  }
}

module registry './modules/registry.bicep' = {
  name: 'registry'
  params: {
    // Alphanumeric only, 5-50 characters.
    name: take('cr${replace(instance, '-', '')}${suffix}', 50)
    location: location
    tags: tags
    pushPrincipalId: identity.outputs.principalId
    manageRoleAssignments: manageRoleAssignments
  }
}

module network './modules/network.bicep' = {
  name: 'network'
  params: {
    name: instance
    location: location
    tags: tags
    sshSourceCidrs: restrictedSshSourceCidrs
    dnsLabel: '${instance}-${suffix}'
  }
}

// cloud-init is shared text; the instance name and admin user are substituted here so the
// file stays readable YAML with obvious placeholders.
var cloudInit = replace(
  replace(loadTextContent('./cloud-init.yaml'), '__CLAW_INSTANCE__', instance),
  '__ADMIN_USER__',
  adminUsername
)

module vm './modules/vm.bicep' = if (deployVm) {
  // Not 'vm': that is the name of the outer deployment the vm pass runs under, and a nested
  // deployment may not overwrite its own active parent.
  name: 'vm-host'
  params: {
    name: instance
    location: location
    tags: tags
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKeys: sshPublicKeys
    identityId: identity.outputs.clawIdentityId
    subnetId: network.outputs.subnetId
    publicIpId: network.outputs.publicIpId
    dataDiskSizeGb: dataDiskSizeGb
    cloudInit: cloudInit
  }
}

output githubIdentityClientId string = identity.outputs.clientId
output githubIdentityPrincipalId string = identity.outputs.principalId
output keyVaultName string = keyVault.outputs.name
output runtimeKeyVaultName string = runtimeVault.outputs.name
output clawIdentityClientId string = identity.outputs.clawClientId
output registryLoginServer string = registry.outputs.loginServer
output registryName string = registry.outputs.name
output networkSecurityGroupName string = network.outputs.nsgName
output publicIp string = network.outputs.publicIp
output publicFqdn string = network.outputs.fqdn
output vmName string = deployVm ? vm!.outputs.vmName : ''
