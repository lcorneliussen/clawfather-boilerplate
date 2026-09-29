// Container registry for the claw image (bin/claw build). Basic SKU; no admin user — CI
// pushes with the deploy identity (AcrPush) and hands the host a short-lived pull token.
@description('Globally unique, alphanumeric, 5-50 chars')
param name string
param location string
param tags object
param pushPrincipalId string
param manageRoleAssignments bool

var acrPushRoleId = '8311e382-0749-4cb8-b61a-304f252e45ec'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: name
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
  }
}

resource push 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (manageRoleAssignments) {
  name: guid(acr.id, pushPrincipalId, acrPushRoleId)
  scope: acr
  properties: {
    principalId: pushPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPushRoleId)
  }
}

output loginServer string = acr.properties.loginServer
output name string = acr.name
