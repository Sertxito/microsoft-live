using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Security.Cryptography;
using Harness.Application.Ports;
using Harness.Domain;
using Harness.Infrastructure.Knowledge;
using Harness.Infrastructure.Search;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace Harness.Tests;

public sealed class DemoFactory : WebApplicationFactory<Program>
{
    private static readonly RsaSecurityKey SigningKey = new(RSA.Create(2048)) { KeyId = "test-only" };
    public RecordingSearch Search { get; } = new();
    public bool CatalogUnavailable { get; set; }
    public string AuthMode { get; init; } = "Jwt";
    public string? ApiKey { get; init; }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseContentRoot(AppContext.BaseDirectory);
        builder.ConfigureLogging(logging => logging.SetMinimumLevel(LogLevel.Warning));
        builder.UseSetting("HARNESS_MODE", "LocalDeterministic");
        builder.UseSetting("HARNESS_AUTH_MODE", AuthMode);
        if (ApiKey is not null) builder.UseSetting("HARNESS_API_KEY", ApiKey);
        builder.UseSetting("HARNESS_AUTHORITY", "https://issuer.test");
        builder.UseSetting("HARNESS_AUTH_AUDIENCE", "harness-tests");
        builder.UseSetting("HARNESS_TELEMETRY_EXPORT", "false");
        builder.ConfigureTestServices(services =>
        {
            services.AddDataProtection().UseEphemeralDataProtectionProvider();
            services.RemoveAll<ITutorialSearch>();
            services.AddSingleton<ITutorialSearch>(Search);
            if (CatalogUnavailable)
            {
                services.RemoveAll<ITutorialCatalog>();
                services.AddSingleton<ITutorialCatalog, UnavailableCatalog>();
            }
            services.PostConfigure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
            {
                var configuration = new OpenIdConnectConfiguration { Issuer = "https://issuer.test" };
                configuration.SigningKeys.Add(SigningKey);
                options.ConfigurationManager = new StaticConfigurationManager<OpenIdConnectConfiguration>(configuration);
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true, ValidIssuer = "https://issuer.test",
                    ValidateAudience = true, ValidAudience = "harness-tests",
                    ValidateLifetime = true, RequireExpirationTime = true,
                    ValidateIssuerSigningKey = true, IssuerSigningKey = SigningKey,
                    ValidAlgorithms = [SecurityAlgorithms.RsaSha256],
                    ClockSkew = TimeSpan.Zero
                };
            });
        });
    }

    public static string Token(bool permitted = true, string issuer = "https://issuer.test",
        string audience = "harness-tests", bool expired = false, bool wrongSignature = false, string? scope = null)
    {
        var claims = new List<Claim>();
        if (permitted) claims.Add(new Claim("roles", "Tutorials.Search"));
        if (scope is not null) claims.Add(new Claim("scp", scope));
        using var otherKey = wrongSignature ? RSA.Create(2048) : null;
        var key = otherKey is null ? SigningKey : new RsaSecurityKey(otherKey);
        var token = new JwtSecurityToken(issuer, audience, claims,
            DateTime.UtcNow.AddMinutes(-10), DateTime.UtcNow.AddMinutes(expired ? -1 : 5),
            new SigningCredentials(key, SecurityAlgorithms.RsaSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public HttpClient AuthorizedClient()
    {
        var client = CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Token());
        return client;
    }

    private sealed class UnavailableCatalog : ITutorialCatalog
    {
        public Task<IReadOnlyList<Tutorial>> ReadAsync(CancellationToken cancellationToken) =>
            throw new IOException("private-storage-path-must-not-leak");
    }
}

public sealed class RecordingSearch : ITutorialSearch
{
    public int Calls { get; private set; }
    public bool Fail { get; set; }
    public int DelayMilliseconds { get; set; }
    public async Task<IReadOnlyList<TutorialSearchHit>> SearchAsync(
        string query, string audience, int maxResults, CancellationToken cancellationToken)
    {
        Calls++;
        if (DelayMilliseconds > 0) await Task.Delay(DelayMilliseconds, cancellationToken);
        if (Fail) throw new Harness.Application.TutorialSearchException("search_unavailable", "The search dependency is unavailable.");
        return await new LocalTutorialSearch(Catalog()).SearchAsync(query, audience, maxResults, cancellationToken);
    }

    public static TutorialDocumentReader Catalog() =>
        new(Path.Combine(AppContext.BaseDirectory, "knowledge", "tutorials", "catalog.json"));
}
