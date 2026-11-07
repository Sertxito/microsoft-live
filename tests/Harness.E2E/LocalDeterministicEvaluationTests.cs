using System.Net.Http.Json;
using System.Text.Json;
using Harness.Contracts;
using Harness.Tests;

namespace Harness.E2E;

public sealed class LocalDeterministicEvaluationTests
{
    [Fact]
    public async Task ReferenceQueriesMeetExactLocalThresholds()
    {
        var cases = JsonSerializer.Deserialize<ReferenceCase[]>(
            await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "evaluations", "reference-cases.json")),
            new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
        await using var factory = new DemoFactory();
        using var client = factory.AuthorizedClient();
        var catalog = await RecordingSearch.Catalog().ReadAsync(default);
        using var thresholds = JsonDocument.Parse(await File.ReadAllTextAsync(
            Path.Combine(AppContext.BaseDirectory, "evaluations", "thresholds.json")));
        var limits = thresholds.RootElement;
        var correlated = 0;
        var sourced = 0;
        var totalResults = 0;
        var unauthorized = 0;
        var covered = 0;
        var generated = 0;
        foreach (var item in cases)
        {
            var response = await client.PostAsJsonAsync("/api/tutorials/search", new { query = item.Query });
            response.EnsureSuccessStatusCode();
            var result = await response.Content.ReadFromJsonAsync<TutorialSearchResponse>();
            Assert.NotNull(result);
            Assert.True(Guid.TryParse(result.CorrelationId, out _));
            correlated++;
            Assert.Null(result.GeneratedAnswer);
            if (result.GeneratedAnswer is not null) generated++;
            Assert.InRange(result.Results.Count, 0, 5);
            Assert.All(result.Results, hit =>
            {
                Assert.True(Uri.TryCreate(hit.Source, UriKind.Absolute, out _));
                sourced++;
                totalResults++;
                Assert.Contains(catalog, document => document.Id == hit.Id && document.Audience == "community" && document.Status == "active");
                if (!catalog.Any(document => document.Id == hit.Id && document.Audience == "community" && document.Status == "active"))
                    unauthorized++;
                Assert.True(hit.Score >= limits.GetProperty("minimumScore").GetDecimal());
            });
            if (item.ExpectedId is null) Assert.Empty(result.Results);
            else Assert.Contains(result.Results, hit => hit.Id == item.ExpectedId);
            covered++;
        }
        Assert.True((double)covered / cases.Length >= limits.GetProperty("expectedResultCoverage").GetDouble());
        Assert.True((double)correlated / cases.Length >= limits.GetProperty("responsesWithCorrelationId").GetDouble());
        Assert.True(totalResults > 0 && (double)sourced / totalResults >= limits.GetProperty("resultsWithSources").GetDouble());
        Assert.Equal(limits.GetProperty("unauthorizedDocuments").GetInt32(), unauthorized);
        Assert.Equal(limits.GetProperty("generatedAnswers").GetInt32(), generated);
    }

    private sealed record ReferenceCase(string Query, string? ExpectedId);
}
