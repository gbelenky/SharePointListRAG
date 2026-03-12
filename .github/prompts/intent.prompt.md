---
name: intent
description: Project intent and architecture overview for SharePoint List Search
---

# SharePoint List Search — Project Intent

## Goal

Enable customers to search FAQ data stored in SharePoint lists using Azure AI Search
with hybrid search (keyword + vector + semantic ranking). Search results include
metadata filtering by language, location, and department. The index is consumed as
a Knowledge Source in Microsoft Copilot Studio.

## Architecture

```
SharePoint Online (FAQ List)
        │
        │  Microsoft Graph API (Sites.Read.All)
        ▼
.NET 8 Console App (ingestion pipeline)
        │
        │  Azure OpenAI (text-embedding-3-small)
        ▼
Azure AI Search (hybrid index: BM25 + HNSW vectors + semantic ranker)
        │
        │  AI Search Knowledge Source connector
        ▼
Microsoft Copilot Studio (end-user chat interface)
```

## Components

### 1. SharePoint FAQ List
A custom SharePoint list with structured FAQ data and metadata columns:
- **Content fields**: Title, Question, Answer
- **Metadata fields**: Category, Language, Location, Department, LastReviewed
- Provisioned via PnP PowerShell (`01-create-sharepoint-list.ps1`)

### 2. Azure AD App Registration
A single app registration used for:
- **Application permission** (Graph `Sites.Read.All`) — .NET app reads list items
- **Delegated permission** (SharePoint `AllSites.Manage`) — PnP PowerShell creates list
- Provisioned via Azure CLI (`00-register-app.ps1`)

### 3. Azure AI Search Index
A hybrid search index (`faq-index`) with:
- Full-text searchable fields for keyword matching (BM25)
- Vector field (`ContentVector`, 1536 dims) for semantic similarity (HNSW, cosine)
- Filterable/facetable metadata fields for OData filtering
- Semantic configuration for reranking
- Created and populated by the .NET console app (`dotnet run -- create-index`, `dotnet run -- ingest`)

### 4. .NET 8 Console App
Three commands:
- `create-index` — Creates the AI Search index schema with vector search + semantic config
- `ingest` — Reads SharePoint list via Graph SDK, generates embeddings, uploads to index
- `test-search` — Validates keyword, vector, hybrid, filtered, semantic, and faceted search

### 5. Copilot Studio Integration
The AI Search index is added as a **Knowledge Source** in Copilot Studio.
Copilot Studio handles query construction and generative answers automatically.
Metadata fields enable filtering by user context (language, department, location).

## Key Design Decisions

- **Hybrid search** (keyword + vector + semantic) provides the best relevance across
  languages and query styles
- **Metadata as filterable fields** (not embedded in text) enables precise OData
  filtering without polluting search relevance
- **Push-based ingestion** (not a built-in indexer) because the SharePoint list indexer
  in AI Search targets document libraries, not lists
- **Single app registration** serves both PnP PowerShell (delegated) and .NET backend
  (application) scenarios
- **AI Search as Knowledge Source** in Copilot Studio is the simplest integration path,
  requiring no custom HTTP connectors or Power Automate flows
