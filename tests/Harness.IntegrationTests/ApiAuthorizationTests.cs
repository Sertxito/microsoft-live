using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Harness.Tests;

namespace Harness.IntegrationTests;

public sealed class ApiAuthorizationTests
{
    [Theory]
    [InlineData("Tutorials.Search", 200)]
    [InlineData("openid Tutorials.Search profile", 200)]
    [InlineData("Tutorials.Search.All", 403)]
    [InlineData("tutorials.search", 403)]
    [InlineData("", 403)]
    public async Task DelegatedScopeRequiresExactPermission(string scope, int expected)
    {
        await using var factory = new DemoFactory();
        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Bearer", DemoFactory.Token(permitted: false, scope: scope));
        var response = await client.PostAsJsonAsync("/api/tutorials/search", new { query = "azure" });
        Assert.Equal(expected, (int)response.StatusCode);
        Assert.Equal(expected == 200 ? 1 : 0, factory.Search.Calls);
    }

    [Theory]
    [InlineData("none", 401)]
    [InlineData("malformed", 401)]
    [InlineData("expired", 401)]
    [InlineData("issuer", 401)]
    [InlineData("audience", 401)]
    [InlineData("signature", 401)]
    [InlineData("role", 403)]
    public async Task InvalidIdentityNeverQueriesIndex(string kind, int expected)
    {
        await using var factory = new DemoFactory();
        using var client = factory.CreateClient();
        var token = kind switch
        {
            "none" => null,
            "malformed" => "not-a-token",
            "expired" => DemoFactory.Token(expired: true),
            "issuer" => DemoFactory.Token(issuer: "https://wrong.test"),
            "audience" => DemoFactory.Token(audience: "other"),
            "signature" => DemoFactory.Token(wrongSignature: true),
            _ => DemoFactory.Token(permitted: false)
        };
        if (token is not null) client.DefaultRequestHeaders.Authorization = new("Bearer", token);
        var response = await client.PostAsJsonAsync("/api/tutorials/search", new { query = "azure" });
        Assert.Equal(expected, (int)response.StatusCode);
        Assert.Equal(0, factory.Search.Calls);
        Assert.True(response.Headers.Contains("X-Correlation-ID"));
    }

    [Theory]
    [InlineData("{\"query\":\"az\"}")]
    [InlineData("{\"query\":\"azure\",\"extra\":true}")]
    [InlineData("{\"query\":\"azure\",\"maxResults\":6}")]
    [InlineData("{\"query\":\"azure\",\"audience\":\"internal\"}")]
    [InlineData("{}")]
    [InlineData("null")]
    [InlineData("invalid")]
    public async Task InvalidInputNeverQueriesIndex(string json)
    {
        await using var factory = new DemoFactory();
        using var client = factory.AuthorizedClient();
        var response = await client.PostAsync("/api/tutorials/search",
            new StringContent(json, System.Text.Encoding.UTF8, "application/json"));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(0, factory.Search.Calls);
    }

    [Fact]
    public async Task OversizedAndRateLimitedRequestsAreControlled()
    {
        await using var factory = new DemoFactory();
        using var client = factory.AuthorizedClient();
        var large = await client.PostAsJsonAsync("/api/tutorials/search", new { query = new string('a', 9000) });
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, large.StatusCode);
        HttpResponseMessage? last = null;
        for (var index = 0; index < 31; index++)
        {
            last?.Dispose();
            last = await client.PostAsJsonAsync("/api/tutorials/search", new { query = "azure" });
        }
        using (last)
            Assert.Equal(HttpStatusCode.TooManyRequests, last?.StatusCode);
    }
}
