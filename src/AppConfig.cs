using DotNetEnv;

namespace SharePointListSearch;

/// <summary>
/// Loads configuration from a .env file in the project root.
/// </summary>
public sealed class AppConfig
{
    // Azure AI Search
    public string SearchEndpoint { get; }
    public string SearchAdminKey { get; }
    public string SearchIndexName { get; }

    // Azure AI Foundry
    public string AiEndpoint { get; }
    public string AiApiKey { get; }
    public string AiEmbeddingDeployment { get; }

    // Microsoft Graph
    public string GraphTenantId { get; }
    public string GraphClientId { get; }
    public string GraphClientSecret { get; }

    // SharePoint
    public string SharePointSiteHostname { get; }
    public string SharePointSitePath { get; }
    public string SharePointListName { get; }

    public AppConfig()
    {
        // Walk up from bin/Debug/net8.0 to find the .env file next to the .csproj
        var dir = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        for (var i = 0; i < 5; i++)
        {
            var envPath = Path.Combine(dir, ".env");
            if (File.Exists(envPath))
            {
                Env.Load(envPath);
                break;
            }
            dir = Directory.GetParent(dir)?.FullName ?? dir;
        }

        SearchEndpoint = Require("AZURE_SEARCH_ENDPOINT");
        SearchAdminKey = Require("AZURE_SEARCH_ADMIN_KEY");
        SearchIndexName = Require("AZURE_SEARCH_INDEX_NAME");

        AiEndpoint = Require("AZURE_AI_ENDPOINT");
        AiApiKey = Environment.GetEnvironmentVariable("AZURE_AI_API_KEY") ?? "";
        AiEmbeddingDeployment = Require("AZURE_AI_EMBEDDING_DEPLOYMENT");

        GraphTenantId = Require("GRAPH_TENANT_ID");
        GraphClientId = Require("GRAPH_CLIENT_ID");
        GraphClientSecret = Require("GRAPH_CLIENT_SECRET");

        SharePointSiteHostname = Require("SHAREPOINT_SITE_HOSTNAME");
        SharePointSitePath = Require("SHAREPOINT_SITE_PATH");
        SharePointListName = Require("SHAREPOINT_LIST_NAME");
    }

    private static string Require(string key)
    {
        var value = Environment.GetEnvironmentVariable(key);
        if (string.IsNullOrWhiteSpace(value))
            throw new InvalidOperationException(
                $"Missing required environment variable: {key}. " +
                $"Copy env.template to .env and fill in the values.");
        return value;
    }
}
