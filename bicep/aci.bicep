//This file stands up a Container Instance as the compute for analysing the AKS Cluster

param nameSeed string
param location string = resourceGroup().location

param image string = 'ghcr.io/boxboat/aks-health-check'

@description('If using ACR for image storage, the Azure Container Registry Login Server')
param acrLoginServer string = ''

@description('The Identity to be inspect the AKS cluster, and if using ACR to pull the image')
param managedIdentityId string

param aksClusterName string
param aksClusterResourceGroupName string = resourceGroup().name

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
    imageRegistryCredentials: acrLoginServer == '' ? [] : [
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
          command: [
            //'./start-from-aci.sh'
            //'echo $PATH'
            //'tail -f /dev/null'
            'az login --identity --verbose'
            'az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME'
            'aks-hc check all -n $CLUSTER_NAME -g $RESOURCE_GROUP | tee $OUTPUT_FILE_NAME'
          ]
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
