using Harness.Domain;

namespace Harness.Application.Ports;

public interface ITutorialSearch
{
    Task<IReadOnlyList<TutorialSearchHit>> SearchAsync(
        string query,
        string audience,
        int maxResults,
        CancellationToken cancellationToken);
}

public sealed record TutorialSearchHit(Tutorial Tutorial, decimal Score);
