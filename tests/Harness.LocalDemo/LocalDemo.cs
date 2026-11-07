using System.Net.Http.Json;
using System.Text.Json;
using Harness.Infrastructure.Telemetry;
using Harness.Tests;
using Microsoft.Extensions.DependencyInjection;

namespace Harness.LocalDemo;

internal static class LocalDemo
{
    public static async Task<int> Main(string[] args)
    {
        await using var factory = new DemoFactory();
        using var anonymous = factory.CreateClient();
        using var client = factory.AuthorizedClient();
        Console.WriteLine("Local HTTP demo: real JWT validation, synthetic catalog, no Azure or MCPEE.");
        Console.WriteLine("Transport: in-process ASP.NET test server; the test issuer is not part of the production API.");
        Console.WriteLine($"Liveness: {(int)(await anonymous.GetAsync("/health/live")).StatusCode}");
        Console.WriteLine($"Anonymous capabilities: {(int)(await anonymous.GetAsync("/api/capabilities")).StatusCode}");
        Console.WriteLine($"Authorized readiness: {(int)(await client.GetAsync("/health/ready")).StatusCode}");
        do
        {
            var query = args.Length > 0 ? string.Join(' ', args) : ReadQuery();
            if (string.IsNullOrWhiteSpace(query)) return 0;
            client.DefaultRequestHeaders.Authorization = new("Bearer", DemoFactory.Token());
            using var response = await client.PostAsJsonAsync("/api/tutorials/search", new { query });
            Console.WriteLine($"HTTP {(int)response.StatusCode}");
            var body = await response.Content.ReadAsStringAsync();
            using var document = JsonDocument.Parse(body);
            Console.WriteLine(JsonSerializer.Serialize(document.RootElement, new JsonSerializerOptions { WriteIndented = true }));
            var id = response.Headers.GetValues("X-Correlation-ID").Single();
            var stages = factory.Services.GetRequiredService<HarnessTelemetry>().Find(id).Select(entry => entry.Stage);
            Console.WriteLine($"Evidence: {string.Join(" -> ", stages)}");
            if (args.Length > 0) return response.IsSuccessStatusCode ? 0 : 1;
        } while (true);
    }

    private static string? ReadQuery()
    {
        Console.Write("Query (empty to exit): ");
        return Console.ReadLine();
    }
}
