namespace Harness.Domain;

public sealed record Tutorial(
    string Id,
    string ClientId,
    string Status,
    string Culture,
    string Audience,
    int Version,
    DateTimeOffset UpdatedAt,
    IReadOnlyList<string> Tags,
    Uri SourceUrl,
    string Title,
    string Summary,
    string Content);
