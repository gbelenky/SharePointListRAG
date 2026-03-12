# Copilot Studio Integration with Azure AI Search FAQ Index

This guide explains how to connect the `faq-index` Azure AI Search index
to a Copilot Studio agent using an **Agent Flow** registered as a **Tool**
(action) with an **HTTP action** for cross-lingual vector search and dynamic
metadata filtering, so FAQ answers are scoped to the user's Location,
Department, and Category context.

---

## Prerequisites

| Item | Details |
|------|---------|
| Azure AI Search | The `faq-index` index created by `dotnet run -- create-index` with data loaded by `dotnet run -- ingest`. Must have the **integrated vectorizer** (`oai-vectorizer`) configured. |
| Search service managed identity | System-assigned managed identity enabled on the search service, with **Cognitive Services OpenAI User** role on the Azure OpenAI resource (required by the integrated vectorizer). |
| Copilot Studio | Access to https://copilotstudio.microsoft.com |
| AI Search admin key | Used in the HTTP action header. Get it from your `.env` file or via `az search admin-key show --service-name <name> --resource-group <rg>`. |

---

## Why HTTP action instead of the managed connector?

Two reasons drive the HTTP action approach:

1. **Dynamic OData filters** — The built-in AI Search Knowledge Source
   connector does not support dynamic filters built from conversation context
   at runtime. To pre-filter results by Location, Department, or Category
   you need to construct the `filter` parameter dynamically.

2. **`disableLocalAuth` compatibility** — The managed Azure AI Search
   connector's "Search vectors with natural language" action requires its
   own OpenAI connection for vectorization. If your subscription enforces
   `disableLocalAuth` on Cognitive Services, the connector cannot
   authenticate and returns **BadGateway** errors. The HTTP action bypasses
   this by calling the REST API directly and relying on the index's
   **integrated vectorizer** (which uses the search service's managed
   identity to call the embedding model server-side).

---

## Step 1: Create or open your Agent

1. Go to [Copilot Studio](https://copilotstudio.microsoft.com) ([docs](https://learn.microsoft.com/microsoft-copilot-studio/fundamentals-what-is-copilot-studio))
2. Create a new agent or open an existing one

## Step 2: Configure Agent Instructions

In the agent's **Instructions** field, add:

```text
You are an internal FAQ assistant for a multinational company.

The FAQ knowledge base contains metadata fields: Category, Location, and Department.
When answering questions:

1. LOCATION: Determine the user's location from their profile or by asking.
   Prefer answers where Location matches the user's region or is 'Global'.
   Do NOT show region-specific answers from other regions unless no match exists.

2. DEPARTMENT: Determine the user's department from their profile or by asking.
   Prefer answers where Department matches the user's team.

3. CATEGORY: Use Category to disambiguate similar questions.
   If the user asks about "access", check whether they mean IT (VPN/password),
   Facilities (building access), or HR (system access) based on context.

4. If multiple results match, present the most specific one first (matching
   Location AND Department) before showing Global/general answers.

5. Always mention which Location and Department an answer applies to.

6. If no results match the user's context, broaden the search and inform the
   user that the answer may not be specific to their region or department.
```

## Step 3: Create the Agent Flow

The Agent Flow calls Azure AI Search via HTTP with:
- **Vector search** using the integrated vectorizer (cross-lingual — queries
  in any language are converted to vectors server-side)
- **Dynamic OData pre-filtering** scoped to user context

### 3.1 Create a new Agent Flow

1. In the left navigation, select **Actions** > **+ Add an action**
2. Choose **Create a new flow** (Agent Flow)
3. Name it, e.g. `AISearchFaQ`

### 3.2 Define trigger inputs

Click on the trigger and add four **input** parameters. Use `*` as the
default / "no filter" placeholder so the flow can be tested without leaving
fields empty (Power Automate requires non-empty trigger values).

| Display title | Type | Description |
|---------------|------|-------------|
| `searchQuery` | String | The user's question |
| `userLocation` | String | User's location, or `*` for no filter |
| `userDepartment` | String | User's department, or `*` for no filter |
| `userCategory` | String | Category filter, or `*` for no filter |

> **Important — trigger property names:** Power Automate auto-generates
> internal property names (`text`, `text_1`, `text_2`, `text_3`) that differ
> from the display titles. All `triggerBody()` expressions must reference
> the **internal names**, not the display titles. Check the code view of the
> trigger to confirm the mapping:
>
> | Display title | Internal property |
> |---------------|-------------------|
> | `searchQuery` | `text` |
> | `userLocation` | `text_1` |
> | `userDepartment` | `text_2` |
> | `userCategory` | `text_3` |
>
> Alternatively, edit the trigger in code view and rename the property keys
> to `searchQuery`, `userLocation`, `userDepartment`, `userCategory` to match
> the display titles. Then the expressions below can use the readable names.
> The expressions below use the **internal names** (`text_1`, etc.).

### 3.3 Build dynamic OData filter expressions

Add **four Compose** actions that individually build each filter clause.
Using separate Compose actions avoids deeply nested `concat`/`if`
expressions and makes the flow easier to debug.

#### 3.3a — LocFilter (Compose)

Click into the **Inputs** field, switch to the **Expression** tab (`fx`),
and paste:
```text
if(or(equals(triggerBody()?['text_1'],'*'),empty(triggerBody()?['text_1'])),'',concat('Location eq ''',triggerBody()?['text_1'],''''))
```

#### 3.3b — DeptFilter (Compose)

```text
if(or(equals(triggerBody()?['text_2'],'*'),empty(triggerBody()?['text_2'])),'',concat('Department eq ''',triggerBody()?['text_2'],''''))
```

#### 3.3c — CatFilter (Compose)

```text
if(or(equals(triggerBody()?['text_3'],'*'),empty(triggerBody()?['text_3'])),'',concat('Category eq ''',triggerBody()?['text_3'],''''))
```

#### 3.3d — BuildFilter1 (Compose)

Joins Location + Department (the `filter()` function does **not** exist in
Power Automate, so use a two-step approach with `if`/`concat` instead):

```text
if(and(not(equals(outputs('LocFilter'),'')),not(equals(outputs('DeptFilter'),'')))  ,concat(outputs('LocFilter'),' and ',outputs('DeptFilter')),concat(outputs('LocFilter'),outputs('DeptFilter')))
```

#### 3.3e — BuildFilter (Compose)

Joins BuildFilter1 + Category:

```text
if(and(not(equals(outputs('BuildFilter1'),'')),not(equals(outputs('CatFilter'),'')))  ,concat(outputs('BuildFilter1'),' and ',outputs('CatFilter')),concat(outputs('BuildFilter1'),outputs('CatFilter')))
```

Example outputs:
- `Location eq 'Europe' and Department eq 'HR'`
- `Department eq 'IT'` (when Location and Category are `*`)
- *(empty string)* when all inputs are `*`

### 3.4 Build the search request body (SearchBody Compose)

Add another **Compose** action named `SearchBody`. In the **Inputs** field,
switch to the [expression editor](https://learn.microsoft.com/power-automate/use-expressions-in-conditions) and create this JSON. Use
**dynamic content chips** (click the lightning-bolt icon) to insert the
trigger and Compose values instead of typing raw `@{...}` expressions:

```json
{
  "search": "<dynamic: text from trigger>",
  "filter": "<dynamic: output of BuildFilter>",
  "select": "Title,Question,Answer,Category,Location,Department",
  "top": 5,
  "vectorQueries": [
    {
      "kind": "text",
      "text": "<dynamic: text from trigger>",
      "fields": "ContentVector",
      "k": 5
    }
  ]
}
```

> **Tip:** To build this in the Power Automate designer, type the static JSON
> first, then delete the placeholder value for `"search"` and click the
> dynamic content icon to pick `text` (searchQuery) from the trigger. Do the
> same for `"filter"` → pick `Outputs` of `BuildFilter` (use the expression
> `outputs('BuildFilter')` if the dynamic content chip is not available),
> and for `"text"` inside `vectorQueries` → pick `text` from the trigger again.
>
> **Common pitfall:** If `"filter"` ends up as an empty string `""` in the
> SearchBody output, the dynamic content chip was not wired correctly. Verify
> via the code view that the filter value is `@{outputs('BuildFilter')}`,
> not a hardcoded empty string.

The `vectorQueries` block is what enables **cross-lingual vector search**.
The integrated vectorizer on the index converts the plain-text `text` value
into an embedding vector server-side — no client-side embedding is needed.

### 3.5 Add HTTP action — call Search REST API

Add an **HTTP** action (the plain Built-in/Premium one, **not** the
"Office 365 HTTP" action which is restricted to Microsoft Graph).

| Field | Value |
|-------|-------|
| Method | `POST` |
| URI | `https://<your-search-service>.search.windows.net/indexes/faq-index/docs/search?api-version=2024-07-01` ([API reference](https://learn.microsoft.com/rest/api/searchservice/documents/search-post)) |
| Headers | `api-key`: *(your admin or query key)* <br> `Content-Type`: `application/json` |
| Body | Select **dynamic content** → pick the `Outputs` of the `SearchBody` Compose |

> **Important:** Do not type raw JSON in the Body field. Select the
> `SearchBody` output via dynamic content so the entire constructed JSON
> object is passed through.

### 3.6 Return results to the agent

Add a **Respond to Copilot** action with a single output variable:

| Output | Type | Value |
|--------|------|-------|
| `searchResults` | String | `body('HTTP')` (dynamic content → Body of the HTTP action) |

The raw JSON response from AI Search is passed directly to Copilot Studio's
LLM orchestrator, which is able to parse the JSON and compose a
natural-language answer. No intermediate Parse JSON or Select/Join actions
are required.

## Step 4: Register the Agent Flow as a Tool

Instead of wiring the flow into a topic, register it as a **Tool** (action)
so the agent's orchestrator can invoke it autonomously whenever a user asks
an FAQ-related question.

1. In your agent, go to **Actions** (left nav) — the Agent Flow you
   created in Step 3 should already appear in the list
2. Click the flow name to open its **details / configuration** pane
3. Verify the **inputs** and **outputs** are visible:
   - Inputs: `searchQuery`, `userLocation`, `userDepartment`, `userCategory`
   - Output: `searchResults`
4. Toggle the action **On** (enabled) if it is not already

The agent's LLM orchestrator will now automatically decide when to call
this tool based on the user's message and the agent instructions you
configured in Step 2. It will:
- Extract the search query from the user's message
- Infer or ask for Location / Department / Category context
- Call the Agent Flow with the appropriate parameters
- Compose a natural-language answer from the JSON response

> **Tip:** You do **not** need to create a dedicated topic or question
> nodes. The orchestrator handles parameter extraction and tool invocation
> based on the agent instructions alone. If the user doesn't provide
> context (e.g. location), the agent will either ask or pass `*` depending
> on how you worded the instructions.

## Step 5: Test in the Flow Designer

Test the flow directly in the Power Automate designer using the **Test**
button (top-right) before testing the full agent.

1. Click **Test** → **Manually** → **Run flow**
2. Enter sample values:

| Test scenario | searchQuery | userLocation | userDepartment | userCategory |
|---------------|-------------|--------------|----------------|--------------|
| Cross-lingual (no filters) | `vacation` | `*` | `*` | `*` |
| Location-scoped | `vacation` | `Europe` | `*` | `*` |
| Department-scoped | `password reset` | `*` | `IT` | `*` |
| Combined filters | `expenses` | `North America` | `Finance` | `*` |

3. Verify the HTTP action returns `200 OK` and the response body contains
   matching FAQ items with the correct metadata values
4. For the cross-lingual test (`vacation` with no filters), expect results
   in multiple languages (e.g. Spanish "solicitud de vacaciones", German
   "Urlaubsantrag", French "demande de congé") — this confirms the
   integrated vectorizer is working

## Step 6: Publish

1. Once satisfied with the test results, click **Publish** on the agent
2. Deploy the agent to your desired channel (Teams, web, etc.)

---

## OData Filter Syntax Reference

```text
# Single filter
Location eq 'Europe'

# Multiple filters (AND)
Location eq 'Europe' and Department eq 'IT'

# Multiple filters (OR within same field)
Location eq 'Europe' or Location eq 'Global'

# Combined
(Location eq 'Europe' or Location eq 'Global') and Department eq 'HR'

# With Category
Location eq 'Europe' and Department eq 'HR' and Category eq 'HR'
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| No results returned | Check that the index has documents (`dotnet run -- test-search`). Verify the OData filter values match exactly (case-sensitive). |
| HTTP 403 from Agent Flow | Verify the API key in the HTTP action header is valid. |
| Empty response body | Ensure the HTTP Body references the `SearchBody` Compose output via dynamic content, not hardcoded JSON. |
| BadGateway with managed connector | This is why we use the HTTP action. The managed connector cannot authenticate when `disableLocalAuth` is enforced. |
| Filter returns empty | Ensure Location/Department/Category values in the filter match the index data exactly. Check available values with `dotnet run -- test-search` (facets section). |
| Vector search not working | Confirm the integrated vectorizer (`oai-vectorizer`) is configured on the index and the search service's managed identity has the **Cognitive Services OpenAI User** role on the Azure OpenAI resource. |
| Semantic ranking not working | Semantic ranking requires **Basic** tier or higher for AI Search. On the Free tier, omit `queryType`/`semanticConfiguration` and rely on vector + keyword hybrid search instead. |
| Agent doesn't ask for context | Check the agent instructions (Step 2) — the orchestrator infers when to ask based on the instruction text. Make the instructions explicit about when to ask for Location/Department. |
| "URI path is not a valid Graph endpoint" | You used the **Office 365 HTTP** action, which only works with Microsoft Graph. Switch to the plain **HTTP** action (Built-in/Premium). |
