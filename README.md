# SharePoint List Search — Azure AI Search Hybrid Search Demo

Index FAQ data from an **existing SharePoint list** into Azure AI Search
with hybrid search (keyword + vector + semantic ranking), including filtering
on metadata fields like language, location, and department. Results are
consumed from Copilot Studio.

## Architecture

```text
SharePoint List (FAQ List)
        |
   .NET console app (Microsoft Graph SDK)
        |
   Azure AI Foundry (text-embedding-3-small)
        |
   Azure AI Search (hybrid index: keyword + vector + integrated vectorizer)
        |
   Copilot Studio Agent Flow  ──HTTP POST──>  AI Search REST API
        |                       (vector search + dynamic OData filters)
   Copilot Studio Agent
```

> **Why not use the built-in SharePoint Online indexer?**
> Azure AI Search has a [SharePoint Online indexer](https://learn.microsoft.com/en-us/azure/search/search-how-to-index-sharepoint-online),
> but it only supports **document libraries** (files like PDFs and Word docs).
> It does **not** support **SharePoint lists** (structured row/column data).
> This project uses a push-based ingestion pipeline via Microsoft Graph to read
> list items, generate vector embeddings, and preserve metadata as filterable
> index fields — none of which the built-in indexer can do for list data.

---

## Prerequisites

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Azure Developer CLI (`azd`)](https://aka.ms/azd) for provisioning
- An Azure subscription
- A **[SharePoint Online](https://learn.microsoft.com/sharepoint/introduction)** site with an existing list you want to index
- An **[App Registration](https://learn.microsoft.com/entra/identity-platform/quickstart-register-app)** with [Microsoft Graph](https://learn.microsoft.com/graph/overview) `Sites.Read.All` (application) permission

### Required RBAC roles

| Role | Scope | Why |
|------|-------|-----|
| **[Cognitive Services OpenAI User](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/ai-machine-learning#cognitive-services-openai-user)** | Azure OpenAI resource (or parent resource group) | Generate embeddings via [`DefaultAzureCredential`](https://learn.microsoft.com/dotnet/api/azure.identity.defaultazurecredential) when API keys are unavailable (`disableLocalAuth`) |
| **[Cognitive Services OpenAI User](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/ai-machine-learning#cognitive-services-openai-user)** | Azure OpenAI resource | Assigned to the **Search service's managed identity** so the [integrated vectorizer](https://learn.microsoft.com/azure/search/vector-search-integrated-vectorization) can call the embedding model at query time |
| **Search Service Contributor** | [Azure AI Search](https://learn.microsoft.com/azure/search/search-what-is-azure-search) resource | Used by the admin key to create/update indexes and upload documents *(granted implicitly when using the admin key from `.env`)* |

> The **Graph** permission (`Sites.Read.All`, application) is configured on the
> App Registration, not via Azure RBAC. The `GRAPH_CLIENT_SECRET` in `.env`
> authenticates via OAuth 2.0 client credentials.

### Expected SharePoint list columns

The ingestion pipeline maps these columns. Your list should have at least
`Title`, `Question`, and `Answer`; the rest are optional metadata for filtering:

| Column       | Type           | Purpose                              |
|--------------|----------------|--------------------------------------|
| Title        | Single line    | Short FAQ title (built-in column)    |
| Question     | Multi-line     | Full question text                   |
| Answer       | Multi-line     | Full answer text                     |
| Category     | Choice         | Filterable/facetable category        |
| Language     | Choice         | e.g. en, de, fr, es                  |
| Location     | Choice         | e.g. Global, North America, Europe   |
| Department   | Choice         | e.g. IT, HR, Finance                 |
| LastReviewed | Date           | When the FAQ was last reviewed       |

---

## Step 0: Register the Microsoft Entra ID App

This creates an App Registration with Microsoft Graph `Sites.Read.All` permission,
a client secret, and a redirect URI for PnP PowerShell.

```powershell
az login
.\00-register-app.ps1
```

The script outputs three values — copy them into your `.env` file (see Step 2):
- `GRAPH_TENANT_ID`
- `GRAPH_CLIENT_ID`
- `GRAPH_CLIENT_SECRET`

---

## Step 1: Provision Azure Resources

Use the Azure Developer CLI to create all required Azure resources:

```bash
azd up
```

This provisions:
- **[Azure AI Search](https://learn.microsoft.com/azure/search/search-what-is-azure-search)** (Free tier) — hosts the hybrid search index
- **[Azure AI Foundry](https://learn.microsoft.com/azure/ai-services/openai/overview)** (S0) — [`text-embedding-3-small`](https://learn.microsoft.com/azure/ai-services/openai/concepts/models) embedding model

The `post-provision` hook automatically populates your `.env` with the
provisioned endpoints, keys, and deployment name.

> **Note:** If your subscription enforces `disableLocalAuth` on Cognitive Services,
> the OpenAI API key cannot be retrieved. The app falls back to **[Microsoft Entra ID](https://learn.microsoft.com/entra/identity-platform/)
> authentication** ([`DefaultAzureCredential`](https://learn.microsoft.com/dotnet/api/azure.identity.defaultazurecredential)) automatically — just ensure your
> identity has the **Cognitive Services OpenAI User** role on the resource:
>
> ```bash
> az role assignment create \
>   --role "Cognitive Services OpenAI User" \
>   --assignee "<your-user-object-id>" \
>   --scope "/subscriptions/<sub-id>/resourceGroups/<rg-name>"
> ```

---

## Step 2: Configure Environment Variables

After `azd up`, the Azure resource values are filled in automatically.
Verify the remaining SharePoint / Graph values are set:

```bash
cp env.template .env   # only needed if .env doesn't exist yet
```

| Variable | Where to find it |
|----------|-----------------|
| `AZURE_SEARCH_ENDPOINT` | *Auto-populated by `azd up`* |
| `AZURE_SEARCH_ADMIN_KEY` | *Auto-populated by `azd up`* |
| `AZURE_AI_ENDPOINT` | *Auto-populated by `azd up`* |
| `AZURE_AI_API_KEY` | *Auto-populated by `azd up`* (optional — leave blank for Entra ID auth) |
| `AZURE_AI_EMBEDDING_DEPLOYMENT` | *Auto-populated by `azd up`* |
| `GRAPH_TENANT_ID` | From Step 0 (App Registration) |
| `GRAPH_CLIENT_ID` | From Step 0 (App Registration) |
| `GRAPH_CLIENT_SECRET` | From Step 0 (App Registration) |
| `SHAREPOINT_SITE_HOSTNAME` | e.g. `contoso.sharepoint.com` |
| `SHAREPOINT_SITE_PATH` | e.g. `/sites/FAQ` |
| `SHAREPOINT_LIST_NAME` | Name of your existing SharePoint list |

---

## Step 3: Create the AI Search Index

```bash
cd src
dotnet run -- create-index
```

This creates the `faq-index` with:
- Searchable text fields: `Title`, `Question`, `Answer`, `Category`
- Filterable/facetable metadata: `Language`, `Location`, `Department`
- Vector field: `ContentVector` (1536 dimensions, HNSW, cosine)
- **[Integrated vectorizer](https://learn.microsoft.com/azure/search/vector-search-integrated-vectorization)** (`oai-vectorizer`) — enables text-to-vector conversion at query time via the search service's system-assigned managed identity, so callers can send plain text and get vector results without embedding client-side
- [Semantic configuration](https://learn.microsoft.com/azure/search/semantic-search-overview) prioritizing `Answer` > `Question`

---

## Step 4: Ingest SharePoint Data

```bash
dotnet run -- ingest
```

This:
1. Connects to SharePoint via [Microsoft Graph SDK](https://learn.microsoft.com/graph/sdks/sdks-overview)
2. Reads all items from the configured list
3. Generates embeddings for each question+answer via Azure AI Foundry
4. Uploads all documents to the AI Search index

---

## Step 5: Test the Search Index

```bash
dotnet run -- test-search
dotnet run -- test-search "How do I reset my password?"
```

Runs 6 test modes:
1. **Keyword search** — plain BM25 text matching
2. **Vector search** — embedding similarity only
3. **Hybrid search** — keyword + vector combined via RRF
4. **Hybrid + metadata filter** — filtered by `Language='en'` and `Department='IT'`
5. **Hybrid + semantic ranking** — with extractive captions
6. **Facets** — shows available filter values and document counts

> **Note:** [Semantic ranking](https://learn.microsoft.com/azure/search/semantic-search-overview) requires the **Basic** tier or higher for AI Search.
> On the Free tier, tests 1–4 and 6 still work; test 5 will return results without reranker scores.

---

## How Search Works — Keyword vs Vector vs Hybrid

The index supports three search strategies. Each has different strengths.

### Keyword Search (BM25)

Traditional full-text search. The engine tokenises the query and documents,
then scores matches by **term frequency** (BM25 algorithm).

| Query | Finds | Misses |
|-------|-------|--------|
| `"reset my password"` | "How do I **reset** my corporate **password**?" (exact word match) | "Wie beantrage ich Urlaub?" (German vacation FAQ — no shared words) |
| `"VPN"` | "How do I connect to the company **VPN**?" | "Comment puis-je demander des congés?" (French leave FAQ) |

**Strengths:** Fast, precise when the user uses the same words as the document.
**Weakness:** Fails completely when the query uses different words or a
different language. `"vacation"` will **not** match the German
`"Urlaubsantrag"` or French `"demande de congé"`.

### Vector Search (Embedding Similarity)

Each document's `Question + Answer` text is converted to a 1536-dimension
vector at ingestion time using `text-embedding-3-small`. At query time,
the user's text is also converted to a vector and the index returns the
**k-nearest neighbours** by cosine similarity.

| Query | Finds (cross-lingual) | Why |
|-------|----------------------|-----|
| `"vacation"` | "Wie beantrage ich **Urlaub**?" (DE), "¿Cómo solicito **vacaciones**?" (ES), "Comment puis-je demander des **congés**?" (FR) | Embeddings capture meaning, not words — "vacation", "Urlaub", "vacaciones", "congés" are nearby in vector space |
| `"parking"` | "How do I get a **parking permit**?" | Semantic similarity to the Facilities FAQ |
| `"building entry"` | "How do I get a **building access card**?" | The meaning of "entry" ≈ "access" in embedding space |

**Strength:** Cross-lingual and synonym-aware — finds results by meaning.
**Weakness:** Can surface loosely related documents that share broad semantic
context but don't actually answer the question.

### Hybrid Search (Keyword + Vector via RRF)

Combines both strategies using **[Reciprocal Rank Fusion (RRF)](https://learn.microsoft.com/azure/search/hybrid-search-ranking)**. Each
strategy returns its own ranked list; RRF merges them so that documents
scoring well in *either* list are promoted.

| Query | Result | Why hybrid wins |
|-------|--------|----------------|
| `"How do I reset my password?"` | Password Reset FAQ ranks #1 with a combined score | Keyword match on "reset" + "password" **and** high vector similarity — both signals agree |
| `"vacation request"` | German, French, Spanish vacation FAQs surface alongside the English process | Vector similarity pulls in cross-lingual results; keyword match boosts any that contain "vacation" or "request" |
| `"expense report Concur"` | Expense Reimbursement FAQ ranks #1 | Keyword matches on "expense" + "Concur" (the app name appears in the answer text), reinforced by vector similarity |

This is the **default strategy used by the Copilot Studio Agent Flow** — the
`SearchBody` includes both a `"search"` text field (BM25) and a `vectorQueries`
block (vector), and AI Search automatically fuses the results.

### Integrated Vectorizer (Query-Time Embedding)

When calling the index from Copilot Studio (or any REST client), you don't
need to generate embeddings client-side. The index has an **integrated
vectorizer** (`oai-vectorizer`) that converts plain text to vectors
server-side using the search service's managed identity to call Azure
OpenAI. This is what enables the `vectorQueries[{kind:"text", text:"..."}]`
syntax in the Agent Flow's HTTP action — just send text, and the index
handles embedding.

### Metadata Filtering (OData `$filter`)

All search modes support **pre-filtering** via OData expressions on the
filterable fields (`Language`, `Location`, `Department`, `Category`).
Filtering is applied **before** scoring, so only matching documents enter
the ranking pipeline.

| Filter | Effect |
|--------|--------|
| `Location eq 'Europe'` | Only FAQs tagged `Europe` — excludes North America, Global, etc. |
| `Location eq 'Europe' and Department eq 'IT'` | Only European IT FAQs |
| *(empty filter)* | All documents are candidates |

Example: a user in Europe asks about parking. The filter `Location eq 'Europe'`
excludes the only parking FAQ (which is tagged `North America`), so the search
returns **zero results** — which is the correct behaviour. The agent should
then tell the user there is no Europe-specific parking policy rather than
fabricating one.

---

## Step 6: Connect to Copilot Studio

See [05-copilot-studio-guide.md](05-copilot-studio-guide.md) for step-by-step
instructions to build an **Agent Flow** in [Copilot Studio](https://learn.microsoft.com/microsoft-copilot-studio/fundamentals-what-is-copilot-studio) and register it as a
**Tool** (action) for the agent. The flow calls the AI Search REST API via an
**HTTP action** with:
- **Cross-lingual vector search** — uses the integrated vectorizer so plain-text
  queries (in any language) are converted to vectors server-side
- **Dynamic OData pre-filtering** — scopes results by Location, Department,
  and Category based on the user's context

> **Why HTTP action instead of the managed AI Search connector?**
> See the [detailed explanation](05-copilot-studio-guide.md#why-http-action-instead-of-the-managed-connector)
> in the Copilot Studio guide. In short: the managed connector fails with
> `disableLocalAuth` and does not support dynamic OData filters.

---

## Next Steps

- **Run batch ingestion in Azure via [ACI](https://learn.microsoft.com/azure/container-instances/container-instances-overview)** — Containerize the .NET app and
  run `dotnet SharePointListSearch.dll -- ingest` as an Azure Container
  Instance (ACI) for reliable one-shot batch ingestion without local
  dependencies. ACI auto-stops when done and you only pay for execution time.
- **Automatic index sync via [Logic App](https://learn.microsoft.com/azure/logic-apps/logic-apps-overview)** — The current `ingest` command is a
  one-shot batch. To keep the index in sync when FAQ items are added or
  updated in SharePoint, create an [Azure Logic App](https://learn.microsoft.com/azure/logic-apps/logic-apps-overview) with the SharePoint
  "When an item is created or modified" trigger that generates an embedding
  (HTTP call to Azure OpenAI) and uploads the document to the search index
  (HTTP call to the AI Search REST API).
- **Enhance agent instructions** — Refine the Copilot Studio agent
  instructions so the orchestrator collects Location and Department from
  the user (or reads them from Entra ID profile claims) before invoking
  the search Tool.
- **Agent publishing** — Publish the Copilot Studio agent to Teams, a web
  channel, or other supported channels.

---

## Project Structure

```text
SharePointListSearch/
├── azure.yaml                       # azd project definition
├── env.template                     # Environment variable template
├── .env                             # Your actual config (not committed)
├── 00-register-app.ps1              # Register Microsoft Entra ID app
├── 01-create-sharepoint-list.ps1    # (Testing) Create sample FAQ list
├── 05-copilot-studio-guide.md       # Copilot Studio integration guide
├── SharePointListSearch.sln         # Solution file
├── infra/                           # [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview) infrastructure-as-code
│   ├── main.bicep                   # Subscription-scoped orchestrator
│   ├── main.bicepparam              # Parameters (reads azd env)
│   ├── modules/
│   │   ├── search.bicep             # Azure AI Search (Free tier)
│   │   └── openai.bicep             # Azure OpenAI + embedding deployment
│   ├── post-provision.ps1           # Populates .env (Windows)
│   └── post-provision.sh            # Populates .env (Linux/macOS)
└── src/
    ├── SharePointListSearch.csproj   # .NET 8 project
    ├── AppConfig.cs                  # Config loader from .env
    ├── FaqDocument.cs                # Strongly-typed index document model
    ├── Program.cs                    # CLI entry point (3 commands)
    ├── CreateIndexCommand.cs         # create-index command
    ├── IngestCommand.cs              # ingest command
    └── TestSearchCommand.cs          # test-search command
```

---

## Appendix: Creating a Sample SharePoint List (for testing)

If you don't have an existing list and want to test the pipeline end-to-end,
the included script creates a sample **FAQ List** with 15 items across multiple
languages, departments, and locations.

### Prerequisites

- [PnP PowerShell](https://pnp.github.io/powershell/) module

```powershell
Install-Module -Name PnP.PowerShell -Scope CurrentUser
```

### Run

```powershell
.\01-create-sharepoint-list.ps1 -SiteUrl "https://yourtenant.sharepoint.com/sites/yoursite" -ClientId "<app-client-id>"
```

Verify at `https://yourtenant.sharepoint.com/sites/yoursite/Lists/FAQ%20List`.
