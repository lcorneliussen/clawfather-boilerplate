// One RBAC Key Vault. main.bicep instantiates it twice: the deploy vault (CI SSH key pair,
// OAuth client, oauth2-proxy cookie secret; read by the GitHub deploy identity) and the
// runtime vault (read by the VM's identity, i.e. the agent). Model-provider keys are in
// neither; they live in the gateway state, entered through the Control UI.
@description('Globally unique vault name (3-24 chars)')
param name string
param location string
param tags object

@description('Principals granted Key Vault Secrets User')
param readerPrincipalIds array

@description('Principal that seeds and rotates secrets (the operator); empty in the pipeline')
param officerPrincipalId string = ''

@allowed(['User', 'ServicePrincipal', 'Group'])
param officerPrincipalType string = 'User'

param manageRoleAssignments bool

var secretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var secretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

resource readers 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in readerPrincipalIds: if (manageRoleAssignments) {
    name: guid(vault.id, principalId, secretsUserRoleId)
    scope: vault
    properties: {
      principalId: principalId
      principalType: 'ServicePrincipal'
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsUserRoleId)
    }
  }
]

resource officer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (manageRoleAssignments && !empty(officerPrincipalId)) {
  name: guid(vault.id, officerPrincipalId, secretsOfficerRoleId)
  scope: vault
  properties: {
    principalId: officerPrincipalId
    principalType: officerPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsOfficerRoleId)
  }
}

output name string = vault.name
output uri string = vault.properties.vaultUri
