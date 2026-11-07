using System.Text.Json;
using System.Text.Json.Serialization;
using Harness.Domain;

namespace Harness.Infrastructure.Knowledge;

public sealed class TutorialSeeder
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
    };

    public async Task<int> SeedAsync(
        IReadOnlyList<Tutorial> tutorials,
        string destination,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(tutorials);
        ArgumentException.ThrowIfNullOrWhiteSpace(destination);
        if (!Path.IsPathFullyQualified(destination))
        {
            throw new ArgumentException("The destination must be an explicit absolute path.", nameof(destination));
        }

        if (tutorials.Count is < 12 or > 20)
        {
            throw new InvalidDataException("The tutorial catalog must contain between 12 and 20 documents.");
        }

        var duplicate = tutorials
            .GroupBy(tutorial => tutorial.Id, StringComparer.Ordinal)
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
        {
            throw new InvalidDataException($"The tutorial catalog contains duplicate id '{duplicate.Key}'.");
        }

        var fullPath = Path.GetFullPath(destination);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);

        Tutorial[] existing = [];
        if (File.Exists(fullPath))
        {
            await using var existingStream = File.OpenRead(fullPath);
            existing = await JsonSerializer.DeserializeAsync<Tutorial[]>(
                existingStream,
                JsonOptions,
                cancellationToken).ConfigureAwait(false)
                ?? throw new InvalidDataException("The destination catalog is invalid.");
        }

        var byId = existing.ToDictionary(tutorial => tutorial.Id, StringComparer.Ordinal);
        foreach (var tutorial in tutorials)
        {
            byId[tutorial.Id] = tutorial;
        }
        if (byId.Count > 20)
            throw new InvalidDataException("The merged catalog would exceed the 20-document demo limit.");

        var serialized = JsonSerializer.SerializeToUtf8Bytes(
            byId.Values.OrderBy(tutorial => tutorial.Id, StringComparer.Ordinal),
            JsonOptions);
        var temporaryPath = $"{fullPath}.{Guid.NewGuid():N}.tmp";
        try
        {
            await File.WriteAllBytesAsync(temporaryPath, serialized, cancellationToken).ConfigureAwait(false);
            File.Move(temporaryPath, fullPath, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }

        return byId.Count;
    }
}
