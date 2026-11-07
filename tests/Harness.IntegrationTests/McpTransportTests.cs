using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Harness.Tests;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;

namespace Harness.IntegrationTests;

public sealed class McpTransportTests
{
    private const string Key = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    [Theory]
    [InlineData(null)]
    [InlineData("wrong-key")]
    public async Task InitializeRequiresKey(string? key)
    {
        await using var factory = new DemoFactory { AuthMode = "ApiKey", ApiKey = Key };
        using var client = factory.CreateClient();
        if (key is not null) client.DefaultRequestHeaders.Add("X-API-Key", key);
        client.DefaultRequestHeaders.Accept.ParseAdd("application/json, text/event-stream");
        var result = await client.PostAsJsonAsync("/mcp", new
        {
            jsonrpc = "2.0", id = 1, method = "initialize",
            @params = new { protocolVersion = "2025-03-26", capabilities = new { }, clientInfo = new { name = "test", version = "1" } }
        });
        Assert.Equal(HttpStatusCode.Unauthorized, result.StatusCode);
        Assert.Equal(0, factory.Search.Calls);
    }

    [Fact]
    public async Task OfficialClientDiscoversAndCallsOnlySearchWithStructuredResults()
    {
        await using var factory = new DemoFactory { AuthMode = "ApiKey", ApiKey = Key };
        using var http = factory.CreateClient();
        http.DefaultRequestHeaders.Add("X-API-Key", Key);
        await using var transport = Transport(http);
        await using var client = await McpClient.CreateAsync(transport);
        var tool = Assert.Single(await client.ListToolsAsync());
        Assert.Equal("buscar_tutoriales", tool.Name);
        var schema = tool.ProtocolTool.InputSchema;
        Assert.Equal("query", Assert.Single(schema.GetProperty("required").EnumerateArray()).GetString());
        Assert.Equal(3, schema.GetProperty("properties").GetProperty("query").GetProperty("minLength").GetInt32());
        Assert.Equal(200, schema.GetProperty("properties").GetProperty("query").GetProperty("maxLength").GetInt32());
        var result = await client.CallToolAsync(tool.Name, new Dictionary<string, object?>
        {
            ["query"] = "container apps", ["maxResults"] = 1, ["audience"] = "community"
        });
        Assert.NotEqual(true, result.IsError);
        var payload = Assert.IsType<JsonElement>(result.StructuredContent);
        Assert.Equal(JsonValueKind.Null, payload.GetProperty("generatedAnswer").ValueKind);
        Assert.Equal("tutorial-001", Assert.Single(payload.GetProperty("results").EnumerateArray()).GetProperty("id").GetString());
        Assert.True(Guid.TryParse(payload.GetProperty("correlationId").GetString(), out _));
        Assert.Single(result.Content.OfType<TextContentBlock>());
        Assert.Equal(1, factory.Search.Calls);
    }

    [Theory]
    [InlineData("ab", 5, "community", false)]
    [InlineData("azure", 0, "community", false)]
    [InlineData("azure", 6, "community", false)]
    [InlineData("azure", 5, "operations", false)]
    [InlineData("azure", 5, "community", true)]
    public async Task InvalidOrUnknownArgumentsAreToolErrorsBeforeSearch(string query, int max, string audience, bool unknown)
    {
        await using var factory = new DemoFactory { AuthMode = "ApiKey", ApiKey = Key };
        using var http = factory.CreateClient();
        http.DefaultRequestHeaders.Add("X-API-Key", Key);
        await using var transport = Transport(http);
        await using var client = await McpClient.CreateAsync(transport);
        var arguments = new Dictionary<string, object?> { ["query"] = query, ["maxResults"] = max, ["audience"] = audience };
        if (unknown) arguments["command"] = "not-allowed";
        var result = await client.CallToolAsync("buscar_tutoriales", arguments);
        Assert.True(result.IsError);
        Assert.Equal("validation_error", Assert.IsType<JsonElement>(result.StructuredContent).GetProperty("code").GetString());
        Assert.Equal(0, factory.Search.Calls);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task ProviderFailuresAndTimeoutAreExplicitCorrelatedToolErrors(bool timeout)
    {
        await using var factory = new DemoFactory { AuthMode = "ApiKey", ApiKey = Key };
        factory.Search.Fail = !timeout;
        factory.Search.DelayMilliseconds = timeout ? 6000 : 0;
        using var http = factory.CreateClient();
        http.DefaultRequestHeaders.Add("X-API-Key", Key);
        await using var transport = Transport(http);
        await using var client = await McpClient.CreateAsync(transport);
        var result = await client.CallToolAsync("buscar_tutoriales", new Dictionary<string, object?> { ["query"] = "azure" });
        Assert.True(result.IsError);
        var payload = Assert.IsType<JsonElement>(result.StructuredContent);
        Assert.Equal(timeout ? "request_timeout" : "search_unavailable", payload.GetProperty("code").GetString());
        Assert.True(Guid.TryParse(payload.GetProperty("correlationId").GetString(), out _));
    }

    [Fact]
    public async Task JwtModeStillRequiresSearchPermissionOnMcp()
    {
        await using var factory = new DemoFactory();
        using var http = factory.CreateClient();
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", DemoFactory.Token(permitted: false));
        http.DefaultRequestHeaders.Accept.ParseAdd("application/json, text/event-stream");
        var result = await http.PostAsJsonAsync("/mcp", new { jsonrpc = "2.0", id = 1, method = "tools/list", @params = new { } });
        Assert.Equal(HttpStatusCode.Forbidden, result.StatusCode);
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", DemoFactory.Token());
        await using var transport = Transport(http);
        await using var client = await McpClient.CreateAsync(transport);
        Assert.Single(await client.ListToolsAsync());
    }

    [Fact]
    public async Task MissingWrongTypeAndUnknownToolCannotInvokeSearch()
    {
        await using var factory = new DemoFactory { AuthMode = "ApiKey", ApiKey = Key };
        using var http = factory.CreateClient();
        http.DefaultRequestHeaders.Add("X-API-Key", Key);
        await using var transport = Transport(http);
        await using var client = await McpClient.CreateAsync(transport);
        foreach (var arguments in new[]
                 {
                     new Dictionary<string, object?>(),
                     new Dictionary<string, object?> { ["query"] = new { invalid = true } },
                     new Dictionary<string, object?> { ["query"] = new string('x', 201) }
                 })
        {
            var result = await client.CallToolAsync("buscar_tutoriales", arguments);
            Assert.True(result.IsError);
        }
        await Assert.ThrowsAsync<ModelContextProtocol.McpProtocolException>(async () =>
            await client.CallToolAsync("execute_command", new Dictionary<string, object?> { ["command"] = "disallowed" }));
        Assert.Equal(0, factory.Search.Calls);
    }

    [Fact]
    public async Task McpAndRestShareBoundedRateLimitWithoutBypass()
    {
        await using var factory = new DemoFactory { AuthMode = "ApiKey", ApiKey = Key };
        using var http = factory.CreateClient();
        http.DefaultRequestHeaders.Add("X-API-Key", Key);
        http.DefaultRequestHeaders.Accept.ParseAdd("application/json, text/event-stream");
        for (var i = 0; i < 30; i++)
        {
            var result = await http.PostAsJsonAsync("/mcp", new { jsonrpc = "2.0", id = i, method = "tools/list", @params = new { } });
            Assert.Equal(HttpStatusCode.OK, result.StatusCode);
        }
        var limited = await http.PostAsJsonAsync("/api/tutorials/search", new { query = "azure" });
        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
        Assert.Equal(0, factory.Search.Calls);
        Assert.Equal(HttpStatusCode.NotFound, (await http.GetAsync("/sse")).StatusCode);
    }

    private static HttpClientTransport Transport(HttpClient client) => new(new HttpClientTransportOptions
    {
        Endpoint = new Uri(client.BaseAddress!, "/mcp"),
        TransportMode = HttpTransportMode.StreamableHttp
    }, client);
}
