using System.Diagnostics;
using Harness.Application.Ports;
using Harness.Contracts;

namespace Harness.Application;

public sealed class TutorialSearchSpecialist(ITutorialSearch search, IRequestEvidence? evidence = null)
{
    public async Task<TutorialSearchResponse> SearchAsync(
        TutorialSearchRequest request,
        string correlationId,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentException.ThrowIfNullOrWhiteSpace(correlationId);

        var query = request.Query?.Trim();
        if (query is null || query.Length is < 3 or > 200)
        {
            throw new TutorialSearchException(
                "validation_error",
                "query must contain between 3 and 200 characters.");
        }

        var maxResults = request.MaxResults ?? 5;
        if (maxResults is < 1 or > 5)
        {
            throw new TutorialSearchException(
                "validation_error",
                "maxResults must be between 1 and 5.");
        }

        if (request.Audience != "community")
        {
            throw new TutorialSearchException(
                "validation_error",
                "audience must be community.");
        }

        var timer = Stopwatch.StartNew();
        cancellationToken.ThrowIfCancellationRequested();
        evidence?.Record(correlationId, "capability.route", "buscar_tutoriales");
        var tutorials = await search.SearchAsync(
            query,
            request.Audience,
            maxResults,
            cancellationToken).ConfigureAwait(false);
        timer.Stop();
        evidence?.Record(correlationId, "search.query", "success", timer.ElapsedMilliseconds, tutorials.Count);

        if (tutorials.Any(hit => hit.Tutorial.Status != "active"
            || hit.Tutorial.Audience != request.Audience
            || !hit.Tutorial.SourceUrl.IsAbsoluteUri
            || hit.Tutorial.SourceUrl.Scheme is not ("https" or "http")
            || string.IsNullOrWhiteSpace(hit.Tutorial.Id)
            || string.IsNullOrWhiteSpace(hit.Tutorial.Title)
            || string.IsNullOrWhiteSpace(hit.Tutorial.Summary)
            || hit.Score < 0))
        {
            throw new TutorialSearchException("invalid_search_response", "The search provider returned an invalid response.");
        }

        var results = tutorials
            .Select(hit => new TutorialSearchResult(
                hit.Tutorial.Id,
                hit.Tutorial.Title,
                hit.Tutorial.Summary,
                hit.Tutorial.Tags,
                hit.Tutorial.SourceUrl.AbsoluteUri,
                hit.Score))
            .Take(maxResults)
            .ToArray();
        evidence?.Record(correlationId, "response.validate", "success", resultCount: results.Length);

        return new TutorialSearchResponse(
            correlationId,
            query,
            results,
            null,
            timer.ElapsedMilliseconds);
    }
}
