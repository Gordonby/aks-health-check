
# BoxBoat's AKS Health Check

[![Known Vulnerabilities](https://snyk.io/test/github/boxboat/aks-health-check/badge.svg)](https://snyk.io/test/github/boxboat/aks-health-check)

This is a client-side tool that uses the Azure CLI to [AKS Best Practice](https://www.the-aks-checklist.com/) checks against the Azure plane and the Kubernetes plane.

## Option A - Run with Current User

``` bash
docker run -it --rm ghcr.io/boxboat/aks-health-check

# Shell in the container
$ az login

$ az account set -s <subscription id>

$ az aks get-credentials -g <resource group> -n <cluster name> --admin

$ aks-hc check all -g <resource group> -n <cluster name>

$ exit
```

## Option B - Run with Azure Service Principal

This option walks you through running the health check using an Azure Managed Identity so that it can be tied to a "service principal". Essentially, it avoids impersoning a user or running with someone's identity.

First, select the Azure subscription.
``` bash
az account set -s <subscription id>
```

Then, set some variables and create a resource group for the container instance.
``` bash
export STORAGE_ACCOUNT="<storage account for logs>"
export FILESHARE_NAME="logs"
export HEALTH_CHECK_RESOURCE_GROUP="<resource group for health check resources>"
export RESOURCE_GROUP="<cluster resource group>"
export LOCATION="eastus"
export MANAGED_IDENTITY_NAME="identity-aks-health-check"

az group create -n $HEALTH_CHECK_RESOURCE_GROUP -l $LOCATION
```

Next, create an Azure managed identity so that the Azure container instance can authenticate with Kubernetes.

``` bash

MANAGED_IDENTITY_CLIENT_ID=$(az identity create -n $MANAGED_IDENTITY_NAME -g $HEALTH_CHECK_RESOURCE_GROUP -l $LOCATION | jq -r '.id')

# for the kubernetes checks
az role assignment create --role "Azure Kubernetes Service Cluster Admin Role" --assignee $MANAGED_IDENTITY_CLIENT_ID
# for the Azure checks
az role assignment create --role "Reader" --assignee $MANAGED_IDENTITY_CLIENT_ID

```

Then, create a storage account with an Azure file share to place our aks-health-check logs. 

``` bash
az storage account create -n $STORAGE_ACCOUNT -g $HEALTH_CHECK_RESOURCE_GROUP

STORAGE_ACCOUNT_KEY=$(az storage account keys list -n $STORAGE_ACCOUNT -g $HEALTH_CHECK_RESOURCE_GROUP | jq -r ".[0].value")

az storage share create --account-name $STORAGE_ACCOUNT --account-key $HEALTH_CHECK_RESOURCE_GROUP -n $FILESHARE_NAME
```

Finally, we can spin up an Azure container instance running the AKS Health Check.
``` bash
# Set the container admin registry password
read CONTAINER_REGISTRY_PASSWORD
az container create --resource-group $RESOURCE_GROUP -l eastus -n aks-health-check\
    --image ghcr.io/boxboat/aks-health-check --assign-identity $MANAGED_IDENTITY_CLIENT_ID \
    --command-line "./start-from-aci.sh" \
    -e CLUSTER_NAME=$CLUSTER_NAME RESOURCE_GROUP=$RESOURCE_GROUP OUTPUT_FILE_NAME=/var/logs/akshc/log$(date +%s).txt \
    --restart-policy Never --azure-file-volume-share-name $FILESHARE_NAME \
    --azure-file-volume-account-name $STORAGE_ACCOUNT --azure-file-volume-account-key $STORAGE_ACCOUNT_KEY \
    --azure-file-volume-mount-path /var/logs/akshc
```

After some time, the container will spin up and run the health checks. 
The logs will be stored in the Azure file share.

### Clean Up

``` bash
az group delete -g $RESOURCE_GROUP
```

## The Checks

There are about 50+ best-practice recommendations for Azure Kubernetes Service (AKS). This tool helps the discovery and examination of 22 checks. The rest are either not automated yet, or they will never be since they require more context about the business, a conversation, and ultimately a judgement call.

| Check ID    | Manual/Automated | Description |
| ----------- | ---------------- | ---------------- |
| `DEV-1`     | Automated | Implement a proper liveness probe |
| `DEV-2`     | Automated | Implement a proper readiness/startup probe |
| `DEV-3`     | Automated | Implement a proper prestop hook |
| `DEV-4`     | Automated | Run more than one replica for your deployments |
| `DEV-5`     | Automated | Apply tags to all resources |
| `DEV-6`     | Automated | Implement autoscaling of your applications |
| `DEV-7`     | Automated | Store secrets in azure key vault |
| `DEV-8`     | Automated | Implement pod identity |
| `DEV-9`     | Automated | Use kubernetes namespaces |
| `DEV-10`    | Automated | Setup resource requests and limits on containers |
| `DEV-11`    | Automated | Specify security context for pods or containers |
| `DEV-12`    | Manual    | Configure pod disruption budgets |
| `IMG-1`     | Manual    | Define image security best practices |
| `IMG-2`     | Manual    | Scan container images during CI/CD pipelines |
| `IMG-3`     | Automated | Allow pulling containers only from allowed registries |
| `IMG-4`     | Automated | Enable runtime security for containerized applications |
| `IMG-5`     | Automated | Configure image pull RBAC for azure container registry |
| `IMG-6`     | Automated | Isolate azure container registries |
| `IMG-7`     | Manual    | Utilize minimal base images |
| `IMG-8`     | Manual    | Forbid the use of privileged containers |
| `CSP-1`     | Manual    | Logically isolate the cluster |
| `CSP-2`     | Automated | Isolate the Kubernetes control plane |
| `CSP-3`     | Automated | Enable Azure AD integration |
| `CSP-4`     | Automated | Enable cluster autoscaling |
| `CSP-5`     | Manual    | Ensure nodes are correctly sized |
| `CSP-6`     | Manual    | Create a process for base image updates |
| `CSP-7`     | Automated | Ensure the Kubernetes dashboard is not installed |
| `CSP-8`     | Manual    | Use Azure AD to pull container images |
| `CSP-9`     | Manual    | Use system and user node pools |
| `DR-1`      | Manual    | Ensure you can perform a whitespace deployment |
| `DR-2`      | Automated | Use availability zones for node pools |
| `DR-3`      | Manual    | Plan for a multi-region deployment |
| `DR-4`      | Manual    | Use Azure traffic manager for cross-region traffic |
| `DR-5`      | Automated | Create a storage migration plan |
| `DR-6`      | Automated | Guarantee SLA for the master control plane |
| `DR-7`      | Manual    | Container registry has geo-replication |
| `STOR-1`    | Manual    | Choose the right storage type |
| `STOR-2`    | Manual    | Size nodes for storage needs |
| `STOR-3`    | Manual    | Dynamically provision volumes when applicable |
| `STOR-4`    | Manual    | Secure and back up your data |
| `STOR-5`    | Manual    | Remove service state from inside containers |
| `NET-1`     | Manual    | Choose an appropriate network model |
| `NET-2`     | Manual    | Plan IP addressing carefully |
| `NET-3`     | Manual    | Distribute ingress traffic |
| `NET-4`     | Manual    | Secure exposed endpoints with a Web Application Firewall (WAF) |
| `NET-5`     | Manual    | Don’t expose ingress on public internet if not necessary |
| `NET-6`     | Manual    | Control traffic flow with network policies |
| `NET-7`     | Manual    | Route egress traffic through a firewall |
| `NET-8`     | Manual    | Do not expose worker nodes to public internet |
| `CSM-1`     | Manual    | Keep Kubernetes version up to date |
| `CSM-2`     | Manual    | Keep nodes up to date and patched |
| `CSM-3`     | Manual    | Monitor cluster security using Azure Security Center |
| `CSM-4`     | Manual    | Provision a log aggregation tool |
| `CSM-5`     | Manual    | Enable master node logs |
| `CSM-6`     | Manual    | Collect metrics |
| `CSM-7`     | Manual    | Configure distributed tracing |
| `CSM-8`     | Manual    | Enable Azure Policy |


## Developing

### Requirements

- [Node v12.22.1](https://github.com/nvm-sh/nvm)
- Azure CLI
- `kubectl`

First, `npm install`.

In VS Code, open the command patellete, then select **Debug: Toggle Auto-Attach** so that any new NodeJS application will attach the VS Code debugger.
Select the "Smart" mode.

Then, from the VS Code terminal, invoke the CLI tool by running it against a cluster.

``` bash
az login 
az set -s <subscription id>
az aks get-credentials -n <cluster name> -g <resource group> --admin
npm start -- check azure -g <cluster resource group> -n <cluster name>
```
