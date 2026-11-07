namespace Harness.Contracts;

public sealed record TutorialSearchRequest(
    string? Query,
    int? MaxResults = null,
    string? Audience = "community");
