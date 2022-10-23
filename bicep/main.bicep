param nameSeed string = 'boxboatAksHC'
param createAcr bool = true
param acrName string = 'cr${nameSeed}${uniqueString(resourceGroup().id, deployment().name)}'
param location string = resourceGroup().location
param aksClusterName string = 'aks-aksboatb'
param aksClusterResourceGroupName string = resourceGroup().name
param storageAccountName string = 'st${nameSeed}${uniqueString(resourceGroup().id, deployment().name)}'
param storageShareName string = 'logs'
param managedIdName string = 'id-${nameSeed}'
param resultsFileName string = 'log${utcNow()}.txt'

@allowed([
  'ACI'
])
param healthCheckCompute string = 'ACI'

//quickly standup a cluster: az deployment group create -g innerloop  --template-uri https://github.com/Azure/AKS-Construction/releases/download/0.9.1/main.json --parameters resourceName=aksboatb JustUseSystemPool=true
resource aks 'Microsoft.ContainerService/managedClusters@2022-08-03-preview' existing = {
  name: aksClusterName
  scope: resourceGroup(aksClusterResourceGroupName)
}

resource acr 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' = if(createAcr) {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

@description('Pulls the source code from the Git repository, builds the Dockerfile to image and stores it in ACR')
module acrImage 'br/public:deployment-scripts/build-acr:1.0.2' = {
  name: '${deployment().name}-buildAcrImage-linux-boxboat'
  params: {
    AcrName: createAcr ? acr.name : acrName
    location: location
    gitRepositoryUrl:  'https://github.com/Gordonby/aks-health-check.git'
    //gitBranch: 'v0.0.6'
    imageName: 'boxboat/aks-health-check'
    managedIdentityName: managedIdentity.name
  }
}

@description('A specific identity that is used by the health check to inspect the AKS cluster')
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: managedIdName
  location: location
}

@description('Assigns the necessary RBAC permissions to the cluster for the identity that does the scanning')
module aksRbac 'aksRbac.bicep' = {
  name: '${deployment().name}-aksRbac'
  scope: resourceGroup(aksClusterResourceGroupName)
  params: {
    aksClusterName: aks.name
    principalId: managedIdentity.properties.principalId
  }
}

@description('Creates the compute needed to analyse the AKS Cluster')
module aci 'aci.bicep' = if(healthCheckCompute == 'ACI') {
  name: '${deployment().name}-aci'
  params: {
    aksClusterName: aksClusterName
    aksClusterResourceGroupName: aksClusterResourceGroupName
    acrLoginServer: acr.properties.loginServer
    image: acrImage.outputs.acrImage
    location: location
    managedIdentityId: managedIdentity.id 
    nameSeed: nameSeed
    storageAccountName: storageAccountName
    storageShareName: storageShareName
    resultsFileName: resultsFileName
  }
  dependsOn: [acrPullRbac]
}

var acrPullRole = resourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
resource acrPullRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = if(createAcr) {
  name: guid(aks.id, managedIdentity.name, acrPullRole)
  scope: acr
  properties: {
    roleDefinitionId: acrPullRole
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
