using System.Net;
using System.Text;
using System.Text.Json;
using Azure;
using Azure.Core.Pipeline;
using Azure.Search.Documents;
using Harness.Application;
using Harness.Infrastructure.Search;

namespace Harness.IntegrationTests;

public sealed class AzureTutorialSearchTests
{
    [Fact]
    public async Task ServerSideFilterAndMinimumScoreUseAzureProviderWithoutNetwork()
    {
        var transport = new SearchTransport(HttpStatusCode.OK, """{"value":[]}""");
        using var http = new HttpClient(transport);
        var options = new SearchClientOptions { Transport = new HttpClientTransport(http) };
        options.Retry.MaxRetries = 0;
        var client = new SearchClient(new Uri("https://demo.search.windows.net"), "tutorials",
            new AzureKeyCredential("test-only-not-a-real-key"), options);
        Assert.Empty(await new AzureTutorialSearch(client, 0.8).SearchAsync("azure", "community", 3, default));
        using var body = JsonDocument.Parse(transport.Body!);
        Assert.Equal("status eq 'active' and audience eq 'community'", body.RootElement.GetProperty("filter").GetString());
        Assert.Equal(3, body.RootElement.GetProperty("top").GetInt32());
        Assert.Equal("azure", body.RootElement.GetProperty("search").GetString());
    }

    [Fact]
    public async Task DependencyFailureIsExplicitNotLocalSuccess()
    {
        using var http = new HttpClient(new SearchTransport(HttpStatusCode.ServiceUnavailable,
            """{"error":{"code":"ServiceUnavailable","message":"private detail"}}"""));
        var options = new SearchClientOptions { Transport = new HttpClientTransport(http) };
        options.Retry.MaxRetries = 0;
        var client = new SearchClient(new Uri("https://demo.search.windows.net"), "tutorials",
            new AzureKeyCredential("test-only-not-a-real-key"), options);
        var error = await Assert.ThrowsAsync<TutorialSearchException>(() =>
            new AzureTutorialSearch(client, 0).SearchAsync("azure", "community", 5, default));
        Assert.Equal("search_unavailable", error.Code);
        Assert.DoesNotContain("private", error.Message);
    }

    private sealed class SearchTransport(HttpStatusCode status, string content) : HttpMessageHandler
    {
        public string? Body { get; private set; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Body = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
            return new HttpResponseMessage(status) { Content = new StringContent(content, Encoding.UTF8, "application/json") };
        }
    }
}
