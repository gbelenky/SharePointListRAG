using System.ClientModel;
using Azure;
using Azure.AI.OpenAI;
using Azure.Search.Documents;
using Azure.Search.Documents.Models;
using Microsoft.Graph;
using Microsoft.Graph.Models;
using Azure.Identity;
using OpenAI.Embeddings;

namespace SharePointListSearch;

/// <summary>
/// Reads FAQ items from a SharePoint list via Microsoft Graph,
/// generates embeddings via Azure OpenAI, and pushes documents
/// into the Azure AI Search index.
/// Run with: dotnet run -- ingest
/// </summary>
public sealed class IngestCommand
{
    public async Task RunAsync()
    {
        var config = new AppConfig();

        // ---- 1. Connect to Microsoft Graph ----
        Console.WriteLine("Connecting to Microsoft Graph ...");
        var graphCredential = new ClientSecretCredential(
            config.GraphTenantId,
            config.GraphClientId,
            config.GraphClientSecret);

        var graphClient = new GraphServiceClient(graphCredential, new[] { "https://graph.microsoft.com/.default" });

        // ---- 2. Resolve the SharePoint site ID ----
        Console.WriteLine($"Resolving site: {config.SharePointSiteHostname}{config.SharePointSitePath} ...");
        var site = await graphClient.Sites[$"{config.SharePointSiteHostname}:{config.SharePointSitePath}"]
            .GetAsync();

        if (site?.Id == null)
            throw new InvalidOperationException("Could not resolve SharePoint site.");

        Console.WriteLine($"Site ID: {site.Id}");

        // ---- 3. Find the FAQ list ----
        Console.WriteLine($"Looking for list: '{config.SharePointListName}' ...");
        var lists = await graphClient.Sites[site.Id].Lists.GetAsync(r =>
        {
            r.QueryParameters.Filter = $"displayName eq '{config.SharePointListName}'";
        });

        var faqList = lists?.Value?.FirstOrDefault()
            ?? throw new InvalidOperationException(
                $"List '{config.SharePointListName}' not found on site.");

        Console.WriteLine($"List ID: {faqList.Id}");

        // ---- 4. Read all list items with field values ----
        Console.WriteLine("Reading list items ...");
        var items = new List<ListItem>();
        var page = await graphClient.Sites[site.Id].Lists[faqList.Id].Items.GetAsync(r =>
        {
            r.QueryParameters.Expand = new[] { "fields" };
        });

        while (page?.Value != null)
        {
            items.AddRange(page.Value);
            if (page.OdataNextLink != null)
            {
                page = await graphClient.Sites[site.Id].Lists[faqList.Id].Items
                    .WithUrl(page.OdataNextLink)
                    .GetAsync();
            }
            else break;
        }

        Console.WriteLine($"Found {items.Count} items.");

        if (items.Count == 0)
        {
            Console.WriteLine("No items to ingest. Exiting.");
            return;
        }

        // ---- 5. Build FaqDocuments ----
        var documents = new List<FaqDocument>();
        foreach (var item in items)
        {
            var fields = item.Fields?.AdditionalData;
            if (fields == null) continue;

            documents.Add(new FaqDocument
            {
                Id = item.Id ?? Guid.NewGuid().ToString(),
                Title = GetField(fields, "Title"),
                Question = GetField(fields, "Question"),
                Answer = GetField(fields, "Answer"),
                Category = GetField(fields, "Category"),
                Language = GetField(fields, "Language"),
                Location = GetField(fields, "Location"),
                Department = GetField(fields, "Department"),
                LastReviewed = GetDateField(fields, "LastReviewed")
            });
        }

        // ---- 6. Generate embeddings ----
        Console.WriteLine("Generating embeddings via Azure AI Foundry ...");
        var openAiClient = string.IsNullOrEmpty(config.AiApiKey)
            ? new AzureOpenAIClient(new Uri(config.AiEndpoint), new DefaultAzureCredential())
            : new AzureOpenAIClient(new Uri(config.AiEndpoint), new ApiKeyCredential(config.AiApiKey));

        var embeddingClient = openAiClient.GetEmbeddingClient(config.AiEmbeddingDeployment);

        foreach (var doc in documents)
        {
            var textToEmbed = $"{doc.Question} {doc.Answer}";
            var embeddingResult = await embeddingClient.GenerateEmbeddingAsync(textToEmbed);
            doc.ContentVector = embeddingResult.Value.ToFloats().ToArray();
            Console.Write(".");
        }
        Console.WriteLine();

        // ---- 7. Push to Azure AI Search ----
        Console.WriteLine("Uploading documents to Azure AI Search ...");
        var searchCredential = new AzureKeyCredential(config.SearchAdminKey);
        var searchClient = new SearchClient(
            new Uri(config.SearchEndpoint),
            config.SearchIndexName,
            searchCredential);

        var batch = IndexDocumentsBatch.Upload(documents);
        var indexResult = await searchClient.IndexDocumentsAsync(batch);

        var succeeded = indexResult.Value.Results.Count(r => r.Succeeded);
        var failed = indexResult.Value.Results.Count(r => !r.Succeeded);

        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine($"Indexing complete: {succeeded} succeeded, {failed} failed.");
        Console.ResetColor();

        if (failed > 0)
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            foreach (var r in indexResult.Value.Results.Where(r => !r.Succeeded))
            {
                Console.WriteLine($"  Failed: {r.Key} — {r.ErrorMessage}");
            }
            Console.ResetColor();
        }
    }

    private static string GetField(IDictionary<string, object> fields, string key)
    {
        return fields.TryGetValue(key, out var val) ? val?.ToString() ?? string.Empty : string.Empty;
    }

    private static DateTimeOffset? GetDateField(IDictionary<string, object> fields, string key)
    {
        if (fields.TryGetValue(key, out var val) && val != null)
        {
            if (val is DateTimeOffset dto) return dto;
            if (DateTimeOffset.TryParse(val.ToString(), out var parsed)) return parsed;
        }
        return null;
    }
}
