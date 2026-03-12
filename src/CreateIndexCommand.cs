using Azure;
using Azure.Search.Documents.Indexes;
using Azure.Search.Documents.Indexes.Models;

namespace SharePointListSearch;

/// <summary>
/// Creates (or updates) the Azure AI Search index with vector search and semantic ranking.
/// Run with: dotnet run -- create-index
/// </summary>
public sealed class CreateIndexCommand
{
    public async Task RunAsync()
    {
        var config = new AppConfig();
        var credential = new AzureKeyCredential(config.SearchAdminKey);
        var indexClient = new SearchIndexClient(new Uri(config.SearchEndpoint), credential);

        Console.WriteLine($"Creating index '{config.SearchIndexName}' on {config.SearchEndpoint} ...");

        // --- Vector search configuration ---
        var vectorSearch = new VectorSearch();
        vectorSearch.Algorithms.Add(new HnswAlgorithmConfiguration("hnsw-algo")
        {
            Parameters = new HnswParameters
            {
                Metric = VectorSearchAlgorithmMetric.Cosine,
                M = 4,
                EfConstruction = 400,
                EfSearch = 500
            }
        });
        vectorSearch.Profiles.Add(new VectorSearchProfile("hnsw-profile", "hnsw-algo")
        {
            VectorizerName = "oai-vectorizer"
        });

        // --- Integrated vectorizer (query-time text → embedding via Azure OpenAI) ---
        vectorSearch.Vectorizers.Add(new AzureOpenAIVectorizer("oai-vectorizer")
        {
            Parameters = new AzureOpenAIVectorizerParameters
            {
                ResourceUri = new Uri(config.AiEndpoint),
                DeploymentName = config.AiEmbeddingDeployment,
                ModelName = config.AiEmbeddingDeployment   // model matches deployment name
            }
        });

        // --- Semantic configuration ---
        var semanticConfig = new SemanticConfiguration("semantic-config", new SemanticPrioritizedFields
        {
            ContentFields =
            {
                new SemanticField("Answer"),
                new SemanticField("Question")
            },
            TitleField = new SemanticField("Title"),
            KeywordsFields =
            {
                new SemanticField("Category"),
                new SemanticField("Department")
            }
        });
        var semanticSearch = new SemanticSearch();
        semanticSearch.Configurations.Add(semanticConfig);

        // --- Build the index definition from the FaqDocument model ---
        var builder = new FieldBuilder();
        var fields = builder.Build(typeof(FaqDocument));

        var index = new SearchIndex(config.SearchIndexName)
        {
            Fields = fields,
            VectorSearch = vectorSearch,
            SemanticSearch = semanticSearch
        };

        var response = await indexClient.CreateOrUpdateIndexAsync(index);

        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine($"Index '{response.Value.Name}' created/updated successfully.");
        Console.ResetColor();
        Console.WriteLine();
        Console.WriteLine("Fields:");
        foreach (var field in response.Value.Fields)
        {
            var flags = new List<string>();
            if (field.IsSearchable == true) flags.Add("searchable");
            if (field.IsFilterable == true) flags.Add("filterable");
            if (field.IsFacetable == true) flags.Add("facetable");
            if (field.IsSortable == true) flags.Add("sortable");
            if (field.IsKey == true) flags.Add("key");
            if (field.VectorSearchDimensions != null) flags.Add($"vector({field.VectorSearchDimensions})");

            Console.WriteLine($"  {field.Name,-20} {field.Type,-30} [{string.Join(", ", flags)}]");
        }
    }
}
