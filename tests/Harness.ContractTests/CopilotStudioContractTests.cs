using System.Net.Http.Json;
using System.Text.Json;
using Harness.Tests;

namespace Harness.ContractTests;

public sealed class CopilotStudioContractTests
{
    [Fact]
    public async Task SwaggerV2MatchesAuthenticatedApiAndHasOnlyHeaderKeySecurity()
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root is not null && !File.Exists(Path.Combine(root.FullName, "Harness.sln"))) root = root.Parent;
        Assert.NotNull(root);
        using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(root.FullName,
            "demo", "copilot-studio", "tutorial-search.swagger.json")));
        var api = document.RootElement;
        Assert.Equal("2.0", api.GetProperty("swagger").GetString());
        Assert.Equal("https", Assert.Single(api.GetProperty("schemes").EnumerateArray()).GetString());
        var security = Assert.Single(api.GetProperty("securityDefinitions").EnumerateObject());
        Assert.Equal("apiKey", security.Value.GetProperty("type").GetString());
        Assert.Equal("header", security.Value.GetProperty("in").GetString());
        Assert.Equal("X-API-Key", security.Value.GetProperty("name").GetString());
        var operation = Assert.Single(api.GetProperty("paths").EnumerateObject());
        Assert.Equal("/api/tutorials/search", operation.Name);
        Assert.Equal("buscar_tutoriales", operation.Value.GetProperty("post").GetProperty("operationId").GetString());
        var key = new string('a', 64);
        await using var factory = new DemoFactory { AuthMode = "ApiKey", ApiKey = key };
        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-API-Key", key);
        var response = await client.PostAsJsonAsync(operation.Name,
            new { query = "container apps", maxResults = 5, audience = "community" });
        response.EnsureSuccessStatusCode();
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var schema = api.GetProperty("definitions").GetProperty("TutorialSearchResponse");
        Assert.Equal(schema.GetProperty("required").EnumerateArray().Select(item => item.GetString()).Order(),
            payload.RootElement.EnumerateObject().Select(item => item.Name).Order());
        Assert.Equal(JsonValueKind.Null, payload.RootElement.GetProperty("generatedAnswer").ValueKind);
        Assert.True(schema.GetProperty("properties").GetProperty("generatedAnswer").GetProperty("x-nullable").GetBoolean());
        Assert.DoesNotContain(key, document.RootElement.GetRawText());
        var definitions = api.GetProperty("definitions");
        var request = definitions.GetProperty("TutorialSearchRequest");
        Assert.Equal("query", Assert.Single(request.GetProperty("required").EnumerateArray()).GetString());
        var properties = request.GetProperty("properties");
        Assert.Equal(3, properties.GetProperty("query").GetProperty("minLength").GetInt32());
        Assert.Equal(200, properties.GetProperty("query").GetProperty("maxLength").GetInt32());
        Assert.Equal(1, properties.GetProperty("maxResults").GetProperty("minimum").GetInt32());
        Assert.Equal(5, properties.GetProperty("maxResults").GetProperty("maximum").GetInt32());
        Assert.Equal("community", Assert.Single(properties.GetProperty("audience").GetProperty("enum").EnumerateArray()).GetString());
        foreach (var result in payload.RootElement.GetProperty("results").EnumerateArray())
            Assert.Equal(definitions.GetProperty("TutorialSearchResult").GetProperty("required")
                    .EnumerateArray().Select(item => item.GetString()).Order(),
                result.EnumerateObject().Select(item => item.Name).Order());
        CheckReferences(api, api);
    }

    private static void CheckReferences(JsonElement element, JsonElement root)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in element.EnumerateObject())
            {
                if (property.Name == "$ref")
                {
                    var reference = property.Value.GetString();
                    Assert.NotNull(reference);
                    Assert.StartsWith("#/", reference);
                    var target = root;
                    foreach (var segment in reference[2..].Split('/')) target = target.GetProperty(segment);
                    Assert.Equal(JsonValueKind.Object, target.ValueKind);
                }
                else CheckReferences(property.Value, root);
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
            foreach (var item in element.EnumerateArray()) CheckReferences(item, root);
    }
}
