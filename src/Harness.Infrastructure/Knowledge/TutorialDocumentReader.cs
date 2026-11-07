using System.Text.Json;
using System.Text.Json.Serialization;
using Harness.Application.Ports;
using Harness.Domain;

namespace Harness.Infrastructure.Knowledge;

public sealed class TutorialDocumentReader(string catalogPath) : ITutorialCatalog
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = false,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
    };

    public async Task<IReadOnlyList<Tutorial>> ReadAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(catalogPath))
        {
            throw new FileNotFoundException("The tutorial catalog was not found.", catalogPath);
        }

        await using var stream = File.OpenRead(catalogPath);
        TutorialCatalogDocument[]? documents;
        try
        {
            documents = await JsonSerializer.DeserializeAsync<TutorialCatalogDocument[]>(
                stream, JsonOptions, cancellationToken).ConfigureAwait(false);
        }
        catch (JsonException exception)
        {
            throw new InvalidDataException("The tutorial catalog is not valid JSON.", exception);
        }

        if (documents is null || documents.Length is < 12 or > 20)
        {
            throw new InvalidDataException("The tutorial catalog must contain between 12 and 20 documents.");
        }

        if (documents.Any(document => document is null))
            throw new InvalidDataException("The tutorial catalog contains an empty document.");
        var tutorials = documents.Select(ToTutorial).ToArray();
        if (tutorials.Select(tutorial => tutorial.Id).Distinct(StringComparer.Ordinal).Count() != tutorials.Length)
        {
            throw new InvalidDataException("The tutorial catalog contains duplicate document ids.");
        }

        return tutorials;
    }

    private static Tutorial ToTutorial(TutorialCatalogDocument document)
    {
        if (string.IsNullOrWhiteSpace(document.Id)
            || string.IsNullOrWhiteSpace(document.ClientId)
            || document.Status is not ("active" or "inactive")
            || string.IsNullOrWhiteSpace(document.Culture)
            || string.IsNullOrWhiteSpace(document.Audience)
            || document.Version < 1
            || document.UpdatedAt == default
            || document.Tags is null
            || document.Tags.Any(string.IsNullOrWhiteSpace)
            || !Uri.TryCreate(document.SourceUrl, UriKind.Absolute, out var sourceUrl)
            || sourceUrl.Scheme is not ("https" or "http")
            || string.IsNullOrWhiteSpace(document.Title)
            || string.IsNullOrWhiteSpace(document.Summary)
            || string.IsNullOrWhiteSpace(document.Content))
        {
            throw new InvalidDataException("A tutorial document has missing or invalid required metadata.");
        }

        return new Tutorial(
            document.Id,
            document.ClientId,
            document.Status,
            document.Culture,
            document.Audience,
            document.Version,
            document.UpdatedAt,
            document.Tags,
            sourceUrl,
            document.Title,
            document.Summary,
            document.Content);
    }
}
