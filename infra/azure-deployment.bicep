// Parameters
param location string = resourceGroup().location
param aksName string = 'mcpgateway-aks'
param acrName string
param cosmosDbAccountName string
param userAssignedIdentityName string = 'mcpgateway-identity'
param appInsightsName string = 'mcpgateway-ai'
param vnetName string = 'mcpgateway-vnet'
param aksSubnetName string = 'aks-subnet'
param appGwSubnetName string = 'appgw-subnet'
param domainNameLabel string

// VNet
resource vnet 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: aksSubnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
      {
        name: appGwSubnetName
        properties: {
          addressPrefix: '10.0.2.0/24'
        }
      }
    ]
  }
}

// ACR
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
    }
    publicNetworkAccess: 'Enabled'
    anonymousPullEnabled: false
    networkRuleBypassOptions: 'AzureServices'
    dataEndpointEnabled: false
    adminUserEnabled: false
  }
}

// AKS Cluster
resource aks 'Microsoft.ContainerService/managedClusters@2023-04-01' = {
  name: aksName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: aksName
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: 2
        vmSize: 'Standard_D4ds_v5'
        osType: 'Linux'
        mode: 'System'
        osSKU: 'Ubuntu'
        vnetSubnetID: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, aksSubnetName)
      }
    ]
    enableRBAC: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    networkProfile: {
      networkPlugin: 'azure'
      loadBalancerSku: 'standard'
      serviceCidr: '192.168.0.0/16'
      dnsServiceIP: '192.168.0.10'
    }
    servicePrincipalProfile: {
      clientId: 'msi'
    }
    addonProfiles: {}
    apiServerAccessProfile: {
      enablePrivateCluster: false
    }
    oidcIssuerProfile: {
      enabled: true
    }
  }
  dependsOn: [vnet]
}

// Attach ACR to AKS
resource acrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, acr.id, 'acrpull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: aks.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Public IP for App Gateway
resource appGwPublicIp 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: '${aksName}-appgw-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: domainNameLabel
    }
  }
}

// Application Gateway
resource appGw 'Microsoft.Network/applicationGateways@2022-09-01' = {
  name: '${aksName}-appgw'
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 1
    }
    gatewayIPConfigurations: [
      {
        name: 'appGwIpConfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, appGwSubnetName)
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwFrontendIP'
        properties: {
           publicIPAddress: {
            id: appGwPublicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'httpPort'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'aksBackendPool'
        properties: {
          backendAddresses: [
            {
              ipAddress: '10.0.0.100'
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'httpSettings'
        properties: {
          port: 80
          protocol: 'Http'
          pickHostNameFromBackendAddress: false
          requestTimeout: 20
        }
      }
    ]
    httpListeners: [
      {
        name: 'httpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', '${aksName}-appgw', 'appGwFrontendIP')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', '${aksName}-appgw', 'httpPort')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'rule1'
        properties: {
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', '${aksName}-appgw', 'httpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', '${aksName}-appgw', 'aksBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', '${aksName}-appgw', 'httpSettings')
          }
          priority: 100
        }
      }
    ]
  }
  dependsOn: [vnet]
}


// User Assigned Identity
resource uai 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: userAssignedIdentityName
  location: location
}

// Federated Credential
resource federatedCred 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: uai
  name: 'aks-adapter-sa-federation'
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: aks.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:adapter:adapter-sa'
  }
}

// CosmosDB Account
resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosDbAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    capabilities: []
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    enableFreeTier: false
  }
}

// Cosmos DB SQL Database
resource cosmosDbSqlDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosDb
  name: 'McpGatewayDb'
  properties: {
    resource: {
      id: 'McpGatewayDb'
    }
  }
}

// Cosmos DB SQL Containers
resource adapterContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  name: 'AdapterContainer'
  parent: cosmosDbSqlDb
  properties: {
    resource: {
      id: 'AdapterContainer'
      partitionKey: {
        paths: ['/id']
        kind: 'Hash'
      }
    }
  }
}

resource cacheContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  name: 'CacheContainer'
  parent: cosmosDbSqlDb
  properties: {
    resource: {
      id: 'CacheContainer'
      partitionKey: {
        paths: ['/id']
        kind: 'Hash'
      }
    }
  }
}

// Cosmos DB Data Contributor Role Assignment to UAI
resource cosmosDbRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-11-15' = {
  parent: cosmosDb
  name: guid(cosmosDb.name, uai.id, 'data-contributor')
  properties: {
    roleDefinitionId: resourceId('Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions', cosmosDb.name, '00000000-0000-0000-0000-000000000002')
    principalId: uai.properties.principalId
    scope: cosmosDb.id
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource flux 'Microsoft.KubernetesConfiguration/fluxConfigurations@2022-03-01' = {
  name: 'aks-adapter-flux'
  scope: aks
  properties: {
    scope: 'cluster'
    namespace: 'adapter'
    sourceKind: 'GitRepository'
    gitRepository: {
      url: 'https://github.com/microsoft/mcp-gateway'
      repositoryRef: {
        branch: 'main'
      }
      timeoutInSeconds: 600
      syncIntervalInSeconds: 60
    }
    kustomizations: {
      appdeploy: {
        path: '.k8s/deployments'
        timeoutInSeconds: 300
        syncIntervalInSeconds: 60
        prune: true
        force: true
      }
    }
  }
}
