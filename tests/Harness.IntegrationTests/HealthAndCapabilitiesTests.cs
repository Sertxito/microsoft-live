using System.Net;
using System.Net.Http.Json;
using Harness.Tests;

namespace Harness.IntegrationTests;

public sealed class HealthAndCapabilitiesTests
{
    [Fact]
    public async Task LiveIsMinimalAndDetailsAreProtected()
    {
        await using var factory = new DemoFactory();
        using var anonymous = factory.CreateClient();
        Assert.Equal("{\"status\":\"live\"}", await anonymous.GetStringAsync("/health/live"));
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync("/health/ready")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync("/api/capabilities")).StatusCode);
        using var client = factory.AuthorizedClient();
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/health/ready")).StatusCode);
        Assert.Contains("buscar_tutoriales", await client.GetStringAsync("/api/capabilities"));
    }

    [Fact]
    public async Task FailureChangesReadinessNotLivenessAndNeverFallsBack()
    {
        await using var factory = new DemoFactory { CatalogUnavailable = true };
        using var client = factory.AuthorizedClient();
        var response = await client.GetAsync("/health/ready");
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain("private-storage", await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/health/live")).StatusCode);
        factory.Search.Fail = true;
        Assert.Equal(HttpStatusCode.ServiceUnavailable,
            (await client.PostAsJsonAsync("/api/tutorials/search", new { query = "azure" })).StatusCode);
    }
}
