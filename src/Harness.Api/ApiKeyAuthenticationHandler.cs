using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace Harness.Api;

public sealed class ApiKeyOptions : AuthenticationSchemeOptions
{
    public string Key { get; set; } = "";
}

public sealed class ApiKeyAuthenticationHandler(
    IOptionsMonitor<ApiKeyOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<ApiKeyOptions>(options, logger, encoder)
{
    public const string SchemeName = "ApiKey";
    public const string HeaderName = "X-API-Key";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue(HeaderName, out var supplied))
            return Task.FromResult(AuthenticateResult.NoResult());
        if (supplied.Count != 1 || supplied[0] is not string key || key.Length != 64)
            return Task.FromResult(AuthenticateResult.Fail("Invalid API key."));
        var expectedHash = SHA256.HashData(Encoding.UTF8.GetBytes(Options.Key));
        var suppliedHash = SHA256.HashData(Encoding.UTF8.GetBytes(key));
        if (!CryptographicOperations.FixedTimeEquals(expectedHash, suppliedHash))
            return Task.FromResult(AuthenticateResult.Fail("Invalid API key."));
        var identity = new ClaimsIdentity(
            [new Claim(ClaimTypes.NameIdentifier, "demo-key"), new Claim("roles", "Tutorials.Search")],
            SchemeName);
        return Task.FromResult(AuthenticateResult.Success(
            new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName)));
    }
}
