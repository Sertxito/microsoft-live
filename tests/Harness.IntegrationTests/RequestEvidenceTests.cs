using System.Net.Http.Json;
using System.Collections.Concurrent;
using System.Diagnostics;
using Harness.Infrastructure.Telemetry;
using Harness.Tests;
using Microsoft.Extensions.DependencyInjection;

namespace Harness.IntegrationTests;

public sealed class RequestEvidenceTests
{
    [Fact]
    public void ExposesOnlySanitizedStageTagsToOptInExporter()
    {
        var observed = new ConcurrentQueue<Activity>();
        using var listener = new ActivityListener
        {
            ShouldListenTo = source => source.Name == HarnessTelemetry.ActivitySourceName,
            Sample = (ref ActivityCreationOptions<ActivityContext> _) => ActivitySamplingResult.AllData,
            ActivityStopped = observed.Enqueue
        };
        ActivitySource.AddActivityListener(listener);
        var id = Guid.NewGuid().ToString("D");
        var telemetry = new HarnessTelemetry();
        using var parent = new Activity("test-request").Start();
        telemetry.Record(id, "search.query", "completed", 42, 3);
        var activity = Assert.Single(observed, item => item.GetTagItem("correlation.id") as string == id);
        Assert.Equal(parent.TraceId, activity.TraceId);
        Assert.Equal(parent.SpanId, activity.ParentSpanId);
        Assert.Equal("search.query", activity.GetTagItem("harness.stage"));
        Assert.Equal(42L, activity.GetTagItem("harness.duration_ms"));
        Assert.Equal(3, activity.GetTagItem("harness.result_count"));
        Assert.Equal(7, activity.TagObjects.Count());
    }

    [Fact]
    public async Task CorrelatesStagesWithoutTokensOrDocuments()
    {
        await using var factory = new DemoFactory();
        using var client = factory.AuthorizedClient();
        var id = Guid.NewGuid().ToString("D");
        client.DefaultRequestHeaders.Add("X-Correlation-ID", id);
        var response = await client.PostAsJsonAsync("/api/tutorials/search", new { query = "azure" });
        response.EnsureSuccessStatusCode();
        Assert.Equal(id, response.Headers.GetValues("X-Correlation-ID").Single());
        var collector = factory.Services.GetRequiredService<HarnessTelemetry>();
        var evidence = collector.Find(id);
        foreach (var stage in new[] { "http.request", "auth.validate", "authorization.check", "capability.route",
            "search.query", "response.validate", "evidence.write" })
            Assert.Contains(evidence, entry => entry.Stage == stage);
        Assert.Empty(collector.Find(Guid.NewGuid().ToString("D")));
        var serialized = System.Text.Json.JsonSerializer.Serialize(evidence);
        Assert.DoesNotContain(client.DefaultRequestHeaders.Authorization!.Parameter!, serialized);
        Assert.DoesNotContain("Recorrido sint", serialized);
        Assert.All(evidence, entry => Assert.False(string.IsNullOrWhiteSpace(entry.Revision)));
    }
}
