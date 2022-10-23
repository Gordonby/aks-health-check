param principalId string
param aksClusterName string

resource aks 'Microsoft.ContainerService/managedClusters@2022-08-03-preview' existing = {
  name: aksClusterName
}

var readerRole = resourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
var clusterAdminRole = resourceId('Microsoft.Authorization/roleDefinitions', '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8')

@description('For the Azure checks')
resource readerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, principalId, readerRole)
  scope: aks
  properties: {
    roleDefinitionId: readerRole
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

@description('For the kubernetes checks')
resource clusterAdminAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, principalId, clusterAdminRole)
  scope: aks
  properties: {
    roleDefinitionId: clusterAdminRole
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
