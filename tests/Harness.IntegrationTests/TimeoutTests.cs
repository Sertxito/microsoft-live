using System.Net;
using System.Net.Http.Json;
using Harness.Application.Ports;
using Harness.Tests;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Harness.IntegrationTests;

public sealed class TimeoutTests
{
    [Fact]
    public async Task DeadlineReturnsCorrelated408()
    {
        await using var factory = new DemoFactory();
        using var host = factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<ITutorialSearch>();
            services.AddSingleton<ITutorialSearch, SlowSearch>();
        }));
        using var client = host.CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Bearer", DemoFactory.Token());
        var response = await client.PostAsJsonAsync("/api/tutorials/search", new { query = "azure" });
        Assert.Equal(HttpStatusCode.RequestTimeout, response.StatusCode);
        Assert.True(response.Headers.Contains("X-Correlation-ID"));
    }

    private sealed class SlowSearch : ITutorialSearch
    {
        public async Task<IReadOnlyList<TutorialSearchHit>> SearchAsync(
            string query, string audience, int maxResults, CancellationToken cancellationToken)
        {
            await Task.Delay(TimeSpan.FromSeconds(30), cancellationToken);
            throw new InvalidOperationException("The deadline should cancel the request.");
        }
    }
}
