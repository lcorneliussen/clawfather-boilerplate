// Deploy identity for GitHub Actions (OIDC, no stored credentials) and the runtime identity
// the VM carries for the agent (reads the runtime Key Vault, nothing else).
param name string
param clawName string
param location string
param tags object
param githubRepository string
param githubRepositoryWithIds string
param githubEnvironment string
param manageRoleAssignments bool

var issuer = 'https://token.actions.githubusercontent.com'
var audiences = ['api://AzureADTokenExchange']

resource githubIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

// The subject form GitHub documents: repo:owner/name:environment:<env>.
resource federationPlain 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: githubIdentity
  name: 'github-environment-${githubEnvironment}'
  properties: {
    issuer: issuer
    subject: 'repo:${githubRepository}:environment:${githubEnvironment}'
    audiences: audiences
  }
}

// Some organisations issue the subject in an id-qualified form (owner@id/name@id). A
// federated credential matches its subject exactly, so that form needs its own entry;
// a login then fails with AADSTS700213 until it exists.
resource federationWithIds 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = if (!empty(githubRepositoryWithIds)) {
  parent: githubIdentity
  name: 'github-environment-${githubEnvironment}-id-subject'
  properties: {
    issuer: issuer
    subject: 'repo:${githubRepositoryWithIds}:environment:${githubEnvironment}'
    audiences: audiences
  }
  dependsOn: [federationPlain] // credentials on one identity must be written serially
}

// Contributor on the resource group: deploy the VM pass, create/delete the per-run SSH NSG
// rule, push to the registry, invoke run-commands. Contributor cannot assign roles.
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

resource contributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (manageRoleAssignments) {
  name: guid(resourceGroup().id, githubIdentity.id, contributorRoleId)
  properties: {
    principalId: githubIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
  }
}

resource clawIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: clawName
  location: location
  tags: tags
}

output principalId string = githubIdentity.properties.principalId
output clientId string = githubIdentity.properties.clientId
output clawIdentityId string = clawIdentity.id
output clawPrincipalId string = clawIdentity.properties.principalId
output clawClientId string = clawIdentity.properties.clientId
