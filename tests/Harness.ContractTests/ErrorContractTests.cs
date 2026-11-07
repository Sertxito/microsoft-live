using System.Net.Http.Json;
using System.Text.Json;
using Harness.Tests;

namespace Harness.ContractTests;

public sealed class ErrorContractTests
{
    [Theory]
    [InlineData("/missing", 404)]
    [InlineData("/api/capabilities", 401)]
    public async Task EarlyErrorsPreserveContract(string path, int status)
    {
        await using var factory = new DemoFactory();
        using var client = factory.CreateClient();
        var response = await client.GetAsync(path);
        Assert.Equal(status, (int)response.StatusCode);
        var error = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
        Assert.Equal(new[] { "code", "correlationId", "message" }, error.EnumerateObject().Select(property => property.Name).Order().ToArray());
        Assert.Equal(response.Headers.GetValues("X-Correlation-ID").Single(), error.GetProperty("correlationId").GetString());
    }
}
