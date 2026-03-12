namespace SharePointListSearch;

class Program
{
    static async Task Main(string[] args)
    {
        if (args.Length == 0)
        {
            PrintUsage();
            return;
        }

        var command = args[0].ToLowerInvariant();

        try
        {
            switch (command)
            {
                case "create-index":
                    await new CreateIndexCommand().RunAsync();
                    break;

                case "ingest":
                    await new IngestCommand().RunAsync();
                    break;

                case "test-search":
                    var query = args.Length > 1 ? args[1] : "How do I reset my password?";
                    await new TestSearchCommand().RunAsync(query);
                    break;

                default:
                    Console.WriteLine($"Unknown command: {command}");
                    PrintUsage();
                    break;
            }
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"Error: {ex.Message}");
            Console.ResetColor();
            Console.WriteLine(ex.StackTrace);
        }
    }

    static void PrintUsage()
    {
        Console.WriteLine("""
            SharePoint List Search — Azure AI Search Hybrid Search Demo

            Usage:
              dotnet run -- create-index          Create the AI Search index schema
              dotnet run -- ingest                 Read SharePoint list & push to index
              dotnet run -- test-search [query]    Run test queries against the index

            Before running, copy env.template to .env and fill in your values.
            """);
    }
}
