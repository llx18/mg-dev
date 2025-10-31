// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using Azure.Core;
using Azure.Identity;
using Microsoft.Azure.Cosmos;
using Microsoft.McpGateway.Management.Store;
using Microsoft.McpGateway.Tools.Contracts;
using Microsoft.McpGateway.Tools.Services;
using System.Text.Json;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);

// Add logging
builder.Services.AddLogging();

// Add HttpClient for tool execution
builder.Services.AddHttpClient();

// Configure tool resource store and tool definition provider
if (builder.Environment.IsDevelopment())
{
    // In development, use in-memory store and JSON file provider
    builder.Services.AddSingleton<IToolResourceStore, InMemoryToolResourceStore>();
    builder.Services.AddSingleton<IToolDefinitionProvider, JsonFileToolDefinitionProvider>();
}
else
{
    // In production, use Cosmos DB store
    var config = builder.Configuration.GetSection("CosmosSettings");
    var connectionString = config["ConnectionString"];
    var credential = new DefaultAzureCredential();
    
    var cosmosClient = string.IsNullOrEmpty(connectionString) 
        ? new CosmosClient(config["AccountEndpoint"], credential, clientOptions: new()
        {
            Serializer = new CosmosSystemTextJsonSerializer(new JsonSerializerOptions()
            {
                DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
            }),
        })
        : new CosmosClient(connectionString);

    builder.Services.AddSingleton(cosmosClient);
    
    // Register IToolResourceStore
    builder.Services.AddSingleton<IToolResourceStore>(sp =>
    {
        var logger = sp.GetRequiredService<ILogger<CosmosToolResourceStore>>();
        return new CosmosToolResourceStore(
            cosmosClient,
            config["DatabaseName"]!,
            "ToolContainer",
            logger);
    });
    
    // Register IToolDefinitionProvider using the store
    builder.Services.AddSingleton<IToolDefinitionProvider, StorageToolDefinitionProvider>();
}

// Register tool executor
builder.Services.AddSingleton<IToolExecutor, HttpToolExecutor>();

// Configure MCP Server
// Note: We need to build a temporary service provider to resolve services in handlers
// This is acceptable because these handlers are registered once at startup
var tempServiceProvider = builder.Services.BuildServiceProvider();
var toolDefinitionProvider = tempServiceProvider.GetRequiredService<IToolDefinitionProvider>();
var toolExecutor = tempServiceProvider.GetRequiredService<IToolExecutor>();

builder.Services.AddMcpServer()
    .WithListToolsHandler(toolDefinitionProvider.ListToolsAsync)
    .WithCallToolHandler(toolExecutor.ExecuteToolAsync)
    .WithHttpTransport();


builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(8000);
});

var app = builder.Build();
app.MapMcp();
await app.RunAsync();

