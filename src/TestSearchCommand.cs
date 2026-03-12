using System.ClientModel;
using Azure;
using Azure.AI.OpenAI;
using Azure.Search.Documents;
using Azure.Search.Documents.Models;
using OpenAI.Embeddings;

namespace SharePointListSearch;

/// <summary>
/// Runs test queries against the FAQ index demonstrating different search modes.
/// Run with: dotnet run -- test-search "How do I reset my password?"
/// </summary>
public sealed class TestSearchCommand
{
    public async Task RunAsync(string query)
    {
        var config = new AppConfig();
        var searchCredential = new AzureKeyCredential(config.SearchAdminKey);
        var searchClient = new SearchClient(
            new Uri(config.SearchEndpoint),
            config.SearchIndexName,
            searchCredential);

        // Generate the query embedding for vector / hybrid searches
        var openAiClient = string.IsNullOrEmpty(config.AiApiKey)
            ? new AzureOpenAIClient(new Uri(config.AiEndpoint), new Azure.Identity.DefaultAzureCredential())
            : new AzureOpenAIClient(new Uri(config.AiEndpoint), new ApiKeyCredential(config.AiApiKey));
        var embeddingClient = openAiClient.GetEmbeddingClient(config.AiEmbeddingDeployment);

        var embeddingResult = await embeddingClient.GenerateEmbeddingAsync(query);
        var queryVector = embeddingResult.Value.ToFloats().ToArray();

        Console.WriteLine($"Query: \"{query}\"\n");

        // ──────────────────────────────────────────────
        // 1. Keyword search (plain text)
        // ──────────────────────────────────────────────
        Console.WriteLine("══════ 1. Keyword Search ══════");
        var keywordOptions = new SearchOptions
        {
            Size = 5,
            Select = { "Id", "Title", "Question", "Answer", "Language", "Location", "Department" },
            IncludeTotalCount = true
        };
        await RunSearchAsync(searchClient, query, keywordOptions);

        // ──────────────────────────────────────────────
        // 2. Pure vector search
        // ──────────────────────────────────────────────
        Console.WriteLine("══════ 2. Vector Search ══════");
        var vectorOptions = new SearchOptions
        {
            Size = 5,
            Select = { "Id", "Title", "Question", "Answer", "Language", "Location", "Department" },
            VectorSearch = new()
            {
                Queries =
                {
                    new VectorizedQuery(queryVector)
                    {
                        KNearestNeighborsCount = 5,
                        Fields = { "ContentVector" }
                    }
                }
            },
            IncludeTotalCount = true
        };
        // pass null search text for pure vector
        await RunSearchAsync(searchClient, null, vectorOptions);

        // ──────────────────────────────────────────────
        // 3. Hybrid search (keyword + vector)
        // ──────────────────────────────────────────────
        Console.WriteLine("══════ 3. Hybrid Search (keyword + vector) ══════");
        var hybridOptions = new SearchOptions
        {
            Size = 5,
            Select = { "Id", "Title", "Question", "Answer", "Language", "Location", "Department" },
            VectorSearch = new()
            {
                Queries =
                {
                    new VectorizedQuery(queryVector)
                    {
                        KNearestNeighborsCount = 5,
                        Fields = { "ContentVector" }
                    }
                }
            },
            IncludeTotalCount = true
        };
        await RunSearchAsync(searchClient, query, hybridOptions);

        // ──────────────────────────────────────────────
        // 4. Hybrid + metadata filter
        // ──────────────────────────────────────────────
        Console.WriteLine("══════ 4. Hybrid + Filter (Language='en', Department='IT') ══════");
        var filteredOptions = new SearchOptions
        {
            Size = 5,
            Select = { "Id", "Title", "Question", "Answer", "Language", "Location", "Department" },
            Filter = "Language eq 'en' and Department eq 'IT'",
            VectorSearch = new()
            {
                Queries =
                {
                    new VectorizedQuery(queryVector)
                    {
                        KNearestNeighborsCount = 5,
                        Fields = { "ContentVector" }
                    }
                }
            },
            IncludeTotalCount = true
        };
        await RunSearchAsync(searchClient, query, filteredOptions);

        // ──────────────────────────────────────────────
        // 5. Hybrid + semantic ranking
        // ──────────────────────────────────────────────
        Console.WriteLine("══════ 5. Hybrid + Semantic Ranking ══════");
        var semanticOptions = new SearchOptions
        {
            Size = 5,
            Select = { "Id", "Title", "Question", "Answer", "Language", "Location", "Department" },
            VectorSearch = new()
            {
                Queries =
                {
                    new VectorizedQuery(queryVector)
                    {
                        KNearestNeighborsCount = 5,
                        Fields = { "ContentVector" }
                    }
                }
            },
            QueryType = SearchQueryType.Semantic,
            SemanticSearch = new()
            {
                SemanticConfigurationName = "semantic-config",
                QueryCaption = new(QueryCaptionType.Extractive)
            },
            IncludeTotalCount = true
        };
        await RunSearchAsync(searchClient, query, semanticOptions);

        // ──────────────────────────────────────────────
        // 6. Facets — show available filter values
        // ──────────────────────────────────────────────
        Console.WriteLine("══════ 6. Facets ══════");
        var facetOptions = new SearchOptions
        {
            Size = 0,
            Facets = { "Language,count:10", "Location,count:10", "Department,count:10", "Category,count:10" },
            IncludeTotalCount = true
        };
        var facetResult = await searchClient.SearchAsync<FaqDocument>("*", facetOptions);
        Console.WriteLine($"Total documents: {facetResult.Value.TotalCount}");
        foreach (var facet in facetResult.Value.Facets)
        {
            Console.WriteLine($"\n  {facet.Key}:");
            foreach (var val in facet.Value)
            {
                Console.WriteLine($"    {val.Value} ({val.Count})");
            }
        }
        Console.WriteLine();
    }

    private static async Task RunSearchAsync(SearchClient client, string? searchText, SearchOptions options)
    {
        var response = await client.SearchAsync<FaqDocument>(searchText, options);
        Console.WriteLine($"Total count: {response.Value.TotalCount}");

        int rank = 1;
        await foreach (var result in response.Value.GetResultsAsync())
        {
            var doc = result.Document;
            Console.WriteLine($"\n  #{rank}  Score: {result.Score:F4}  " +
                              $"RerankerScore: {result.SemanticSearch?.RerankerScore?.ToString("F4") ?? "n/a"}");
            Console.WriteLine($"        Title:      {doc.Title}");
            Console.WriteLine($"        Question:   {Truncate(doc.Question, 80)}");
            Console.WriteLine($"        Answer:     {Truncate(doc.Answer, 80)}");
            Console.WriteLine($"        Language:   {doc.Language}  |  Location: {doc.Location}  |  Dept: {doc.Department}");

            if (result.SemanticSearch?.Captions is { Count: > 0 } captions)
            {
                Console.WriteLine($"        Caption:    {captions[0].Text}");
            }

            rank++;
        }
        Console.WriteLine();
    }

    private static string Truncate(string text, int maxLength)
    {
        if (string.IsNullOrEmpty(text)) return string.Empty;
        return text.Length <= maxLength ? text : text[..maxLength] + "...";
    }
}
