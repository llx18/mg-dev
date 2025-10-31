// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System.Text.Json;
using Microsoft.McpGateway.Management.Contracts;
using Microsoft.McpGateway.Tools.Contracts;
using ModelContextProtocol.Protocol;
using ModelContextProtocol.Server;

namespace Microsoft.McpGateway.Tools.Services
{
    /// <summary>
    /// Implementation that loads tool definitions from a JSON file.
    /// </summary>
    public class JsonFileToolDefinitionProvider : IToolDefinitionProvider
    {
        private const int CacheExpirationMinutes = 5;

        private readonly string configFilePath;
        private readonly ILogger<JsonFileToolDefinitionProvider> logger;
        private readonly IWebHostEnvironment environment;
        private List<ToolDefinition>? cachedTools;
        private DateTime lastLoadTime;

        /// <summary>
        /// Initializes a new instance of the <see cref="JsonFileToolDefinitionProvider"/> class.
        /// </summary>
        public JsonFileToolDefinitionProvider(
            IConfiguration configuration,
            IWebHostEnvironment environment,
            ILogger<JsonFileToolDefinitionProvider> logger)
        {
            this.environment = environment;
            this.logger = logger;

            // Get path from configuration, or use default
            var configuredPath = configuration.GetValue<string>("ToolDefinitionsPath");

            if (!string.IsNullOrEmpty(configuredPath))
            {
                // If absolute path, use as-is
                if (Path.IsPathRooted(configuredPath))
                {
                    this.configFilePath = configuredPath;
                }
                else
                {
                    // Relative path - resolve from content root
                    this.configFilePath = Path.Combine(environment.ContentRootPath, configuredPath);
                }
            }
            else
            {
                // Default: look for mcp-tools.json in content root
                this.configFilePath = Path.Combine(environment.ContentRootPath, "mcp-tools.json");
            }

            this.logger.LogInformation("Tool definitions path: {Path}", this.configFilePath);
        }

        public async Task<List<ToolDefinition>> GetToolDefinitionsAsync(CancellationToken cancellationToken = default)
        {
            var cacheExpiration = TimeSpan.FromMinutes(CacheExpirationMinutes);

            // Simple caching mechanism
            if (this.cachedTools != null && DateTime.UtcNow - this.lastLoadTime < cacheExpiration)
            {
                return this.cachedTools;
            }

            try
            {
                if (!File.Exists(this.configFilePath))
                {
                    this.logger.LogWarning("Tool definitions file not found at {Path}", this.configFilePath);
                    return new List<ToolDefinition>();
                }

                var jsonContent = await File.ReadAllTextAsync(this.configFilePath, cancellationToken);

                // Deserialize the root object with "tools" array
                var rootObject = JsonSerializer.Deserialize<ToolsRoot>(
                    jsonContent,
                    new JsonSerializerOptions
                    {
                        PropertyNameCaseInsensitive = true,
                        ReadCommentHandling = JsonCommentHandling.Skip,
                        AllowTrailingCommas = true
                    });

                this.cachedTools = rootObject?.Tools ?? new List<ToolDefinition>();
                this.lastLoadTime = DateTime.UtcNow;

                this.logger.LogInformation("Loaded {Count} tool definitions from {Path}", this.cachedTools.Count, this.configFilePath);
                return this.cachedTools;
            }
            catch (Exception ex)
            {
                this.logger.LogError(ex, "Failed to load tool definitions from {Path}", this.configFilePath);
                return new List<ToolDefinition>();
            }
        }

        /// <inheritdoc/>
        public async Task<ToolDefinition?> GetToolDefinitionAsync(string toolName, CancellationToken cancellationToken = default)
        {
            var tools = await this.GetToolDefinitionsAsync(cancellationToken);
            return tools.FirstOrDefault(t => t.Name.Equals(toolName, StringComparison.OrdinalIgnoreCase));
        }

        public async ValueTask<ListToolsResult> ListToolsAsync(RequestContext<ListToolsRequestParams> context, CancellationToken cancellationToken = default)
        {
            this.logger.LogInformation("Listing available MCP tools");

            // Load tool definitions
            var toolDefinitions = await this.GetToolDefinitionsAsync(cancellationToken);

            // Convert to MCP Protocol Tools
            var tools = toolDefinitions.Select(td => td.Tool).ToList();

            this.logger.LogInformation("Returning {Count} tools", tools.Count);

            return new ListToolsResult
            {
                Tools = tools,
                NextCursor = null
            };
        }

        /// <summary>
        /// Root object for deserializing the mcp-tools.json file.
        /// </summary>
        private class ToolsRoot
        {
            [System.Text.Json.Serialization.JsonPropertyName("tools")]
            public List<ToolDefinition>? Tools { get; set; }
        }
    }
}
