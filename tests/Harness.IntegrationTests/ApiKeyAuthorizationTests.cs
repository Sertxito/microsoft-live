using System.Net;
using System.Net.Http.Json;
using Harness.Tests;

namespace Harness.IntegrationTests;

public sealed class ApiKeyAuthorizationTests
{
    private static readonly string Key = new('a', 64);

    [Theory]
    [InlineData("missing", 401)]
    [InlineData("wrong", 401)]
    [InlineData("short", 401)]
    [InlineData("multiple", 401)]
    [InlineData("bearer", 401)]
    [InlineData("query", 401)]
    [InlineData("valid", 200)]
    public async Task OnlyExactHeaderKeyCanRetrieve(string kind, int expected)
    {
        await using var factory = new DemoFactory { AuthMode = "ApiKey", ApiKey = Key };
        using var client = factory.CreateClient();
        if (kind is "valid" or "wrong" or "short" or "multiple")
            client.DefaultRequestHeaders.Add("X-API-Key",
                kind == "wrong" ? new string('b', 64) : kind == "short" ? "short" : Key);
        if (kind == "multiple") client.DefaultRequestHeaders.Add("X-API-Key", Key);
        if (kind == "bearer") client.DefaultRequestHeaders.Authorization = new("Bearer", DemoFactory.Token());
        var path = "/api/tutorials/search" + (kind == "query" ? $"?apiKey={Key}" : "");
        var response = await client.PostAsJsonAsync(path, new { query = "azure" });
        Assert.Equal(expected, (int)response.StatusCode);
        Assert.Equal(expected == 200 ? 1 : 0, factory.Search.Calls);
        Assert.True(response.Headers.Contains("X-Correlation-ID"));
        Assert.DoesNotContain(Key, await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task KeyModeKeepsHealthProtectedAndDoesNotEnableJwtFallback()
    {
        await using var factory = new DemoFactory { AuthMode = "ApiKey", ApiKey = Key };
        using var client = factory.CreateClient();
        Assert.Equal("{\"status\":\"live\"}", await client.GetStringAsync("/health/live"));
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/health/ready")).StatusCode);
        client.DefaultRequestHeaders.Add("X-API-Key", Key);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/health/ready")).StatusCode);
        Assert.Contains("\"authMode\":\"ApiKey\"", await client.GetStringAsync("/api/capabilities"));
    }

    [Fact]
    public async Task DefaultJwtModeIgnoresApiKeyHeader()
    {
        await using var factory = new DemoFactory { ApiKey = Key };
        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-API-Key", Key);
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await client.PostAsJsonAsync("/api/tutorials/search", new { query = "azure" })).StatusCode);
        Assert.Equal(0, factory.Search.Calls);
    }
}
