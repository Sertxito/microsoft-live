using System.Text.RegularExpressions;
using Harness.Application.Ports;
using Harness.Domain;

namespace Harness.Infrastructure.Search;

public sealed partial class LocalTutorialSearch(ITutorialCatalog catalog, decimal minimumScore = 0.2m) : ITutorialSearch
{
    public async Task<IReadOnlyList<TutorialSearchHit>> SearchAsync(
        string query,
        string audience,
        int maxResults,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (minimumScore is <= 0 or > 1)
            throw new ArgumentOutOfRangeException(nameof(minimumScore));
        var tutorials = await catalog.ReadAsync(cancellationToken).ConfigureAwait(false);
        var queryTerms = Terms().Matches(query)
            .Select(match => match.Value)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        if (queryTerms.Length == 0) return [];

        return tutorials
            .Where(tutorial => tutorial.Status == "active"
                && string.Equals(tutorial.Audience, audience, StringComparison.Ordinal))
            .Select(tutorial => new
            {
                Tutorial = tutorial,
                Score = queryTerms.Count(term => ContainsTerm(tutorial, term))
            })
            .Where(candidate => (decimal)candidate.Score / queryTerms.Length >= minimumScore)
            .OrderByDescending(candidate => candidate.Score)
            .ThenBy(candidate => candidate.Tutorial.Id, StringComparer.Ordinal)
            .Take(maxResults)
            .Select(candidate => new TutorialSearchHit(
                candidate.Tutorial,
                (decimal)candidate.Score / queryTerms.Length))
            .ToArray();
    }

    private static bool ContainsTerm(Tutorial tutorial, string term)
    {
        var content = string.Join(
            ' ',
            tutorial.Title,
            tutorial.Summary,
            string.Join(' ', tutorial.Tags),
            tutorial.Content);
        return Terms().Matches(content)
            .Any(match => string.Equals(match.Value, term, StringComparison.OrdinalIgnoreCase));
    }

    [GeneratedRegex(@"[\p{L}\p{N}]+", RegexOptions.CultureInvariant)]
    private static partial Regex Terms();
}
