namespace Harness.Contracts;

public sealed record TutorialSearchResult(
    string Id,
    string Title,
    string Summary,
    IReadOnlyList<string> Tags,
    string Source,
    decimal Score);

public sealed record TutorialSearchResponse(
    string CorrelationId,
    string Query,
    IReadOnlyList<TutorialSearchResult> Results,
    string? GeneratedAnswer,
    long DurationMs);
