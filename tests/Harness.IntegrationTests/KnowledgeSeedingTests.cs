using Harness.Infrastructure.Knowledge;
using Harness.Tests;

namespace Harness.IntegrationTests;

public sealed class KnowledgeSeedingTests
{
    [Fact]
    public async Task SecondSeedIsIdempotentAndPreservesMetadata()
    {
        var path = Path.Combine(Path.GetTempPath(), $"harness-catalog-{Guid.NewGuid():N}.json");
        try
        {
            var catalog = await RecordingSearch.Catalog().ReadAsync(default);
            Assert.InRange(catalog.Count, 12, 20);
            var seeder = new TutorialSeeder();
            Assert.Equal(catalog.Count, await seeder.SeedAsync(catalog, path, default));
            var first = await File.ReadAllTextAsync(path);
            Assert.Equal(catalog.Count, await seeder.SeedAsync(catalog, path, default));
            Assert.Equal(first, await File.ReadAllTextAsync(path));
            Assert.Equal(catalog.Count, (await new TutorialDocumentReader(path).ReadAsync(default)).Count);
            await Assert.ThrowsAsync<InvalidDataException>(() =>
                seeder.SeedAsync(Enumerable.Repeat(catalog[0], 12).ToArray(), path, default));
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    [Fact]
    public async Task InvalidCatalogsNeverReturnSuccessfulEmptyResults()
    {
        var path = Path.Combine(Path.GetTempPath(), $"harness-invalid-{Guid.NewGuid():N}.json");
        try
        {
            await File.WriteAllTextAsync(path, "not json");
            await Assert.ThrowsAsync<InvalidDataException>(() => new TutorialDocumentReader(path).ReadAsync(default));
            await File.WriteAllTextAsync(path, "[]");
            await Assert.ThrowsAsync<InvalidDataException>(() => new TutorialDocumentReader(path).ReadAsync(default));
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
}
