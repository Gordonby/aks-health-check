param nameSeed string = 'boxboatAksHC'
param createAcr bool = true
param acrName string = 'cr${nameSeed}${uniqueString(resourceGroup().id, deployment().name)}'
param location string = resourceGroup().location
param aksClusterName string
param aksClusterResourceGroupName string = resourceGroup().name
param storageAccountName string = 'st${nameSeed}${uniqueString(resourceGroup().id, deployment().name)}'
param storageShareName string = 'logs'
param managedIdName string = 'id-${nameSeed}'
param resultsFileName string = 'log${utcNow()}.txt'

var cleanStorageAccountName = take(toLower(storageAccountName),24)
var storageMountPath= '/var/logs/akshc'

resource aks 'Microsoft.ServiceFabric/managedClusters@2022-08-01-preview' existing = {
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

module acrImage 'br/public:deployment-scripts/build-acr:1.0.1' = {
  name: 'buildAcrImage-linux-boxboat'
  params: {
    AcrName: acrName
    location: location
    gitRepositoryUrl:  'https://github.com/Gordonby/aks-health-check.git'
    imageName: 'boxboat/aks-health-check'
    //managedIdentityName: managedIdentity.name
  }
}

resource storageaccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: cleanStorageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Premium_LRS'
  }
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: managedIdName
  location: location
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, managedIdentity.id, 'roleDefinitionId')
  scope: aks
  properties: {
    roleDefinitionId: 'roleDefinitionId'
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}


resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2021-03-01' = {
  name: 'aci-${nameSeed}'
  location: location
  identity: {
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
    type: 'UserAssigned'
  }
  properties: {
    containers: [
      {
        name: nameSeed
        properties: {
          image: acrImage.outputs.acrImage
          resources: {
            requests: {
              cpu: 1
              memoryInGB: 2
            }
          }
          environmentVariables: [
            {
              name: 'CLUSTER_NAME'
              value: aksClusterName
            }
            {
              name: 'RESOURCE_GROUP'
              value: aksClusterResourceGroupName
            }
            {
              name: 'OUTPUT_FILE_NAME'
              value: '${storageMountPath}/${resultsFileName}'
            }
          ]
          volumeMounts: [
            {
              name: storageShareName
              mountPath: storageMountPath
            }
          ]
        }
      }
    ]
    restartPolicy: 'Never'
    osType: 'Linux'
    volumes: [
      {
        name: storageShareName
        azureFile: {
          shareName: storageShareName
          storageAccountName: storageaccount.name
          storageAccountKey: storageaccount.listKeys().keys[0].value
        }
      }
    ]
  }
}
