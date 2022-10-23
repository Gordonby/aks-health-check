//This file stands up a Container Instance as the compute for analysing the AKS Cluster

param nameSeed string
param location string

param image string

@description('The Azure Container Registry where the image is stored')
param acrLoginServer string

@description('The Identity to be used to pull the image from ACR, and inspect the AKS cluster')
param managedIdentityId string

param aksClusterName string
param aksClusterResourceGroupName string

param storageAccountName string
param storageShareName string
param resultsFileName string

var storageMountPath= '/var/logs/akshc'
var cleanStorageAccountName = take(toLower(storageAccountName),24)
var outputFileName = '${storageMountPath}/${resultsFileName}'

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2021-10-01' = {
  name: 'aci-${nameSeed}'
  location: location
  identity: {
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
    type: 'UserAssigned'
  }
  properties: {
    imageRegistryCredentials: [
      {
        server: acrLoginServer
        identity:  managedIdentityId
      }
    ]
    containers: [
      {
        name: toLower(nameSeed)
        properties: {
          image: image
          //command: ['./start-from-aci.sh']
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
              value: outputFileName
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
          storageAccountKey: storageaccount.listKeys().keys[0].value //Unfortunately the storage mounting has to use keys, and not the managed identity
        }
      }
    ]
  }
}

@description('The storage account to persist the AKS Health Check results')
resource storageaccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: cleanStorageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  
  resource files 'fileServices' = {
    name: 'default'
    
    resource logs 'shares' = {
      name: storageShareName
    }
  }
}

output resultsFileName string = outputFileName
