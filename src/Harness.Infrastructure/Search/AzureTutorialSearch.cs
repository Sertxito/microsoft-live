using Azure;
using Azure.Search.Documents;
using Azure.Search.Documents.Models;
using Harness.Application;
using Harness.Application.Ports;
using Harness.Domain;

namespace Harness.Infrastructure.Search;

public sealed class AzureTutorialSearch(SearchClient client, double minimumScore) : ITutorialSearch
{
    public async Task<IReadOnlyList<TutorialSearchHit>> SearchAsync(
        string query, string audience, int maxResults, CancellationToken cancellationToken)
    {
        if (!double.IsFinite(minimumScore) || minimumScore < 0)
            throw new ArgumentOutOfRangeException(nameof(minimumScore));
        var options = new SearchOptions
        {
            Size = maxResults,
            QueryType = SearchQueryType.Simple,
            SearchMode = SearchMode.All,
            Filter = SearchFilter.Create($"status eq 'active' and audience eq {audience}")
        };
        foreach (var field in new[] { "id", "clientId", "status", "culture", "audience", "version",
            "updatedAt", "tags", "sourceUrl", "title", "summary", "content" })
            options.Select.Add(field);
        try
        {
            var response = await client.SearchAsync<SearchDocument>(query, options, cancellationToken);
            var hits = new List<TutorialSearchHit>();
            await foreach (var hit in response.Value.GetResultsAsync().WithCancellation(cancellationToken))
            {
                if (hit.Score is not double score || !double.IsFinite(score) || score < minimumScore) continue;
                var document = hit.Document;
                var tutorial = new Tutorial(
                    document.GetString("id"), document.GetString("clientId"), document.GetString("status"),
                    document.GetString("culture"), document.GetString("audience"),
                    document.GetInt32("version") ?? throw new InvalidDataException("Missing tutorial version."),
                    document.GetDateTimeOffset("updatedAt") ?? throw new InvalidDataException("Missing tutorial date."),
                    document.GetStringCollection("tags").ToArray(), new Uri(document.GetString("sourceUrl")),
                    document.GetString("title"), document.GetString("summary"), document.GetString("content"));
                hits.Add(new(tutorial, (decimal)score));
            }
            return hits;
        }
        catch (RequestFailedException exception)
        {
            throw new TutorialSearchException("search_unavailable", "The search dependency is unavailable.", exception);
        }
    }

    public async Task CheckReadyAsync(CancellationToken cancellationToken)
    {
        try { await client.GetDocumentCountAsync(cancellationToken); }
        catch (RequestFailedException exception)
        {
            throw new TutorialSearchException("search_unavailable", "The search dependency is unavailable.", exception);
        }
    }
}
