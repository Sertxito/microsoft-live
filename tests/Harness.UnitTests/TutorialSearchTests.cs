using Harness.Application;
using Harness.Application.Ports;
using Harness.Contracts;
using Harness.Domain;
using Harness.Infrastructure.Search;
using Harness.Tests;

namespace Harness.UnitTests;

public sealed class TutorialSearchTests
{
    [Theory]
    [InlineData(0, false)]
    [InlineData(2, false)]
    [InlineData(3, true)]
    [InlineData(200, true)]
    [InlineData(201, false)]
    public async Task QueryBoundaries(int length, bool valid)
    {
        var search = new RecordingSearch();
        var handler = new TutorialSearchSpecialist(search);
        var action = () => handler.SearchAsync(new(new string('a', length)), "test", default);
        if (valid) await action();
        else await Assert.ThrowsAsync<TutorialSearchException>(action);
        Assert.Equal(valid ? 1 : 0, search.Calls);
    }

    [Theory]
    [InlineData(null, true)]
    [InlineData(0, false)]
    [InlineData(1, true)]
    [InlineData(5, true)]
    [InlineData(6, false)]
    public async Task ResultCountBoundaries(int? count, bool valid)
    {
        var handler = new TutorialSearchSpecialist(new RecordingSearch());
        var action = () => handler.SearchAsync(new("azure", count), "test", default);
        if (valid) Assert.InRange((await action()).Results.Count, 0, count ?? 5);
        else await Assert.ThrowsAsync<TutorialSearchException>(action);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("internal")]
    [InlineData("Community")]
    public async Task RejectsUnsupportedAudience(string? audience) =>
        await Assert.ThrowsAsync<TutorialSearchException>(() =>
            new TutorialSearchSpecialist(new RecordingSearch()).SearchAsync(new("azure", Audience: audience), "test", default));

    [Fact]
    public async Task SourcesFiltersEmptyAndNoGeneration()
    {
        var handler = new TutorialSearchSpecialist(new RecordingSearch());
        var result = await handler.SearchAsync(new("azure"), "test", default);
        Assert.NotEmpty(result.Results);
        Assert.All(result.Results, hit => Assert.StartsWith("https://", hit.Source));
        Assert.Null(result.GeneratedAnswer);
        Assert.Empty((await handler.SearchAsync(new("zzzznonexistent"), "test", default)).Results);
        Assert.Empty((await handler.SearchAsync(new("!!!"), "test", default)).Results);
        var catalog = await RecordingSearch.Catalog().ReadAsync(default);
        Assert.All(result.Results, hit => Assert.Contains(catalog,
            document => document.Id == hit.Id && document.Status == "active" && document.Audience == "community"));
    }

    [Fact]
    public async Task CancellationIsNotSuccess()
    {
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            new TutorialSearchSpecialist(new RecordingSearch()).SearchAsync(new("azure"), "test", cancelled.Token));
    }

    [Fact]
    public async Task InvalidProviderSourcesAreRejectedNotSilentlyDropped()
    {
        var tutorial = (await RecordingSearch.Catalog().ReadAsync(default))[0];
        var provider = new FixedSearch([new(tutorial with { SourceUrl = new Uri("file:///private") }, 1)]);
        await Assert.ThrowsAsync<TutorialSearchException>(() =>
            new TutorialSearchSpecialist(provider).SearchAsync(new("azure"), "test", default));
    }

    [Fact]
    public async Task MinimumScoreIsProviderSpecific()
    {
        var search = new LocalTutorialSearch(RecordingSearch.Catalog(), 1m);
        Assert.Empty(await search.SearchAsync("azure zzzzz", "community", 5, default));
    }

    private sealed class FixedSearch(IReadOnlyList<TutorialSearchHit> hits) : ITutorialSearch
    {
        public Task<IReadOnlyList<TutorialSearchHit>> SearchAsync(string query, string audience, int maxResults,
            CancellationToken cancellationToken) => Task.FromResult(hits);
    }
}
