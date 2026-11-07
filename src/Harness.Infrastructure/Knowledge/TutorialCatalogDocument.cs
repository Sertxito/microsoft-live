namespace Harness.Infrastructure.Knowledge;

internal sealed record TutorialCatalogDocument(
    string? Id,
    string? ClientId,
    string? Status,
    string? Culture,
    string? Audience,
    int Version,
    DateTimeOffset UpdatedAt,
    string[]? Tags,
    string? SourceUrl,
    string? Title,
    string? Summary,
    string? Content);
