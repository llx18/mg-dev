// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using Microsoft.McpGateway.Management.Contracts;

namespace Microsoft.McpGateway.Management.Store
{
    /// <summary>
    /// In-memory implementation of the tool resource store for development.
    /// </summary>
    public class InMemoryToolResourceStore : IToolResourceStore
    {
        private readonly Dictionary<string, ToolResource> _tools = new();
        private readonly SemaphoreSlim _lock = new(1, 1);

        public async Task<ToolResource?> TryGetAsync(string name, CancellationToken cancellationToken)
        {
            await _lock.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                return _tools.TryGetValue(name, out var tool) ? tool : null;
            }
            finally
            {
                _lock.Release();
            }
        }

        public async Task UpsertAsync(ToolResource tool, CancellationToken cancellationToken)
        {
            await _lock.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                _tools[tool.Name] = tool;
            }
            finally
            {
                _lock.Release();
            }
        }

        public async Task DeleteAsync(string name, CancellationToken cancellationToken)
        {
            await _lock.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                _tools.Remove(name);
            }
            finally
            {
                _lock.Release();
            }
        }

        public async Task<IEnumerable<ToolResource>> ListAsync(CancellationToken cancellationToken)
        {
            await _lock.WaitAsync(cancellationToken).ConfigureAwait(false);
            try
            {
                return _tools.Values.ToList();
            }
            finally
            {
                _lock.Release();
            }
        }
    }
}
