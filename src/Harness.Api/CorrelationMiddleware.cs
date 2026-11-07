using System.Diagnostics;
using Harness.Infrastructure.Telemetry;

namespace Harness.Api;

public sealed class CorrelationMiddleware(RequestDelegate next)
{
    public const string ItemKey = "Harness.CorrelationId";

    public async Task InvokeAsync(HttpContext context, HarnessTelemetry telemetry)
    {
        var supplied = context.Request.Headers["X-Correlation-ID"].ToString();
        var correlationId = Guid.TryParse(supplied, out var parsed) ? parsed.ToString("D") : Guid.NewGuid().ToString("D");
        context.Items[ItemKey] = correlationId;
        context.Response.Headers["X-Correlation-ID"] = correlationId;
        Activity.Current?.SetTag("correlation.id", correlationId);
        var timer = Stopwatch.StartNew();
        try { await next(context); }
        finally
        {
            telemetry.Record(correlationId, "http.request", context.Response.StatusCode.ToString(), timer.ElapsedMilliseconds);
            telemetry.Record(correlationId, "evidence.write", "local");
        }
    }
}
