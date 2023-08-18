param name string
param location string = resourceGroup().location
param tags object = {}

param allowedOrigins array = []
param applicationInsightsName string = ''
param appServicePlanName string
@secure()
param appSettings object = {}
param keyVaultName string
param serviceName string = 'api'
param storageAccountName string

param useVirtualNetworkIntegration bool = false
param useVirtualNetworkPrivateEndpoint bool = false
param virtualNetworkName string = ''
param virtualNetworkPrivateEndpointSubnetName string = ''
param virtualNetworkIntegrationSubnetName string = ''

resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = if (useVirtualNetworkPrivateEndpoint || useVirtualNetworkIntegration) {
  name: virtualNetworkName

  resource privateEndpointSubnet 'subnets' existing = {
    name: virtualNetworkPrivateEndpointSubnetName
  }

  resource integrationSubnet 'subnets' existing = {
    name: virtualNetworkIntegrationSubnetName
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
  name: storageAccountName
}

module functionPlan '../core/host/functionplan.bicep' = {
  name: 'plan-${name}'
  params: {
    location: location
    tags: tags
    OperatingSystem: 'Linux'
    name: appServicePlanName
    planSku: 'EP1'
  }
}

module api '../core/host/functions.bicep' = {
  name: '${serviceName}-functions-dotnet-module'
  params: {
    name: name
    location: location
    tags: union(tags, { 'azd-service-name': serviceName })
    allowedOrigins: allowedOrigins
    alwaysOn: false
    applicationInsightsName: applicationInsightsName
    appServicePlanId: functionPlan.outputs.planId
    keyVaultName: keyVaultName
    functionsWorkerRuntime: 'dotnet-isolated'
    runtimeName: 'dotnetcore'
    runtimeVersion: '6.0'
    extensionVersion: '~4'
    vnetRouteAllEnabled: true
    kind: 'functionapp,linux'
    storageAccountName: storageAccountName
    scmDoBuildDuringDeployment: false
    enableOryxBuild: false
    functionsRuntimeScaleMonitoringEnabled: true
    virtualNetworkName: vnet.name
    virtualNetworkIntegrationSubnetName: vnet::integrationSubnet.name
    virtualNetworkPrivateEndpointSubnetName: vnet::privateEndpointSubnet.name
    useVirtualNetworkIntegration: useVirtualNetworkIntegration

    // NOTE: Cannot set private endpoint on the Function app and have Static Web App communicate with the Function app.
    // Setting the private endpoint option to FALSE.
    useVirtualNetworkPrivateEndpoint: false

    appSettings: union(appSettings,
      {
        // Needed for EP plans
        WEBSITE_CONTENTSHARE: name

        // TODO: Move to Key Vault (need to use user-assigned managed identity). See https://github.com/Azure/azure-functions-host/issues/7094
        WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

        // Needed when the backend storage account is private.
        WEBSITE_CONTENTOVERVNET: 1
        WEBSITE_SKIP_CONTENTSHARE_VALIDATION: 1
      })
  }
}

output SERVICE_API_IDENTITY_PRINCIPAL_ID string = api.outputs.identityPrincipalId
output SERVICE_API_NAME string = api.outputs.name
output SERVICE_API_URI string = api.outputs.uri
