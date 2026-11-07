using System.Net.Http.Json;
using System.Text.Json;
using Harness.Tests;

namespace Harness.ContractTests;

public sealed class PublicOpenApiTests
{
    [Fact]
    public async Task OpenApiDescribesActualSuccessAndErrorShapeWithoutInternalOperations()
    {
        await using var factory = new DemoFactory();
        using var client = factory.AuthorizedClient();
        using var document = JsonDocument.Parse(await client.GetStringAsync("/openapi.json"));
        var api = document.RootElement;
        Assert.Single(api.GetProperty("paths").EnumerateObject());
        var operation = api.GetProperty("paths").GetProperty("/api/tutorials/search").GetProperty("post");
        Assert.Equal("buscar_tutoriales", operation.GetProperty("operationId").GetString());
        foreach (var code in new[] { "200", "400", "401", "403", "408", "413", "429", "500", "503" })
            Assert.True(operation.GetProperty("responses").TryGetProperty(code, out _));
        var response = await client.PostAsJsonAsync("/api/tutorials/search", new { query = "azure" });
        response.EnsureSuccessStatusCode();
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var expected = api.GetProperty("components").GetProperty("schemas").GetProperty("TutorialSearchResponse")
            .GetProperty("required").EnumerateArray().Select(property => property.GetString()).Order().ToArray();
        Assert.Equal(expected, payload.RootElement.EnumerateObject().Select(property => property.Name).Order().ToArray());
        Assert.Equal(JsonValueKind.Null, payload.RootElement.GetProperty("generatedAnswer").ValueKind);
    }
}
