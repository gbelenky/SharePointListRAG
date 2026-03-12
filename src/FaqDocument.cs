using Azure.Search.Documents.Indexes;
using Azure.Search.Documents.Indexes.Models;

namespace SharePointListSearch;

/// <summary>
/// Represents a single FAQ document in the Azure AI Search index.
/// </summary>
public sealed class FaqDocument
{
    [SimpleField(IsKey = true, IsFilterable = true)]
    public string Id { get; set; } = string.Empty;

    [SearchableField(AnalyzerName = LexicalAnalyzerName.Values.EnLucene)]
    public string Title { get; set; } = string.Empty;

    [SearchableField(AnalyzerName = LexicalAnalyzerName.Values.EnLucene)]
    public string Question { get; set; } = string.Empty;

    [SearchableField(AnalyzerName = LexicalAnalyzerName.Values.EnLucene)]
    public string Answer { get; set; } = string.Empty;

    [SearchableField(IsFilterable = true, IsFacetable = true)]
    public string Category { get; set; } = string.Empty;

    [SimpleField(IsFilterable = true, IsFacetable = true)]
    public string Language { get; set; } = string.Empty;

    [SimpleField(IsFilterable = true, IsFacetable = true)]
    public string Location { get; set; } = string.Empty;

    [SimpleField(IsFilterable = true, IsFacetable = true)]
    public string Department { get; set; } = string.Empty;

    [SimpleField(IsFilterable = true, IsSortable = true)]
    public DateTimeOffset? LastReviewed { get; set; }

    [VectorSearchField(VectorSearchDimensions = 1536, VectorSearchProfileName = "hnsw-profile")]
    public IReadOnlyList<float>? ContentVector { get; set; }
}
