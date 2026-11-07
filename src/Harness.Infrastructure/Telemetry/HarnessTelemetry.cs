using System.Collections.Concurrent;
using System.Diagnostics;
using Harness.Application.Ports;

namespace Harness.Infrastructure.Telemetry;

public sealed record RequestEvidence(
    string CorrelationId, string Stage, string Outcome, long DurationMs,
    int? ResultCount, string Version, string Revision, DateTimeOffset Timestamp);

public sealed class HarnessTelemetry : IRequestEvidence
{
    public const string ActivitySourceName = "Harness.Evidence";
    private static readonly ActivitySource Source = new(ActivitySourceName);
    private readonly ConcurrentQueue<RequestEvidence> entries = new();
    private const int Capacity = 4096;
    private readonly string version = typeof(HarnessTelemetry).Assembly.GetName().Version?.ToString() ?? "unknown";
    private readonly string revision = Environment.GetEnvironmentVariable("CONTAINER_APP_REVISION") ?? "local";

    public void Record(string correlationId, string stage, string outcome, long durationMs = 0, int? resultCount = null)
    {
        entries.Enqueue(new(correlationId, stage, outcome, durationMs, resultCount, version, revision, DateTimeOffset.UtcNow));
        using var activity = Source.StartActivity(stage, ActivityKind.Internal, default(ActivityContext),
            new ActivityTagsCollection
            {
                ["correlation.id"] = correlationId,
                ["harness.stage"] = stage,
                ["harness.outcome"] = outcome,
                ["harness.duration_ms"] = durationMs,
                ["harness.result_count"] = resultCount,
                ["service.version"] = version,
                ["harness.revision"] = revision
            });
        while (entries.Count > Capacity) entries.TryDequeue(out _);
    }

    public IReadOnlyList<RequestEvidence> Find(string correlationId) =>
        entries.Where(entry => entry.CorrelationId == correlationId).ToArray();
}
