using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Threading.RateLimiting;
using Azure.Identity;
using Azure.Monitor.OpenTelemetry.AspNetCore;
using Azure.Search.Documents;
using Harness.Api;
using Harness.Application;
using Harness.Application.Ports;
using Harness.Contracts;
using Harness.Infrastructure.Knowledge;
using Harness.Infrastructure.Search;
using Harness.Infrastructure.Telemetry;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using OpenTelemetry.Trace;
using ModelContextProtocol.AspNetCore;

if (args.FirstOrDefault() is "search" or "seed")
{
    try
    {
        var catalog = new TutorialDocumentReader(CatalogPath());
        if (args[0] == "search")
        {
            if (args.Length < 2) throw new ArgumentException("Usage: Harness.Api search <query>");
            var response = await new TutorialSearchSpecialist(new LocalTutorialSearch(catalog))
                .SearchAsync(new(string.Join(' ', args.Skip(1))), Guid.NewGuid().ToString("D"), CancellationToken.None);
            Console.WriteLine(JsonSerializer.Serialize(response, new JsonSerializerOptions(JsonSerializerDefaults.Web)));
        }
        else
        {
            if (args.Length != 2 || !Path.IsPathFullyQualified(args[1]))
                throw new ArgumentException("Usage: Harness.Api seed <absolute-catalog-path>");
            var count = await new TutorialSeeder().SeedAsync(await catalog.ReadAsync(CancellationToken.None),
                args[1], CancellationToken.None);
            Console.WriteLine($"Seeded {count} tutorials to the selected local destination.");
        }
        return 0;
    }
    catch (Exception exception) when (exception is ArgumentException or IOException or JsonException or TutorialSearchException)
    {
        Console.Error.WriteLine(exception.Message);
        return 2;
    }
}

var builder = WebApplication.CreateBuilder(args);
var mode = builder.Configuration["HARNESS_MODE"] ?? "LocalDeterministic";
var authority = builder.Configuration["HARNESS_AUTHORITY"];
var audience = builder.Configuration["HARNESS_AUTH_AUDIENCE"];
var authMode = builder.Configuration["HARNESS_AUTH_MODE"] ?? "Jwt";
var apiKey = builder.Configuration["HARNESS_API_KEY"];
var exportSetting = builder.Configuration["HARNESS_TELEMETRY_EXPORT"] ?? "false";
if (!bool.TryParse(exportSetting, out var exportTelemetry)
    || (exportTelemetry && (mode != "AzureIntegrated"
        || string.IsNullOrWhiteSpace(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]))))
{
    Console.Error.WriteLine("Telemetry export requires AzureIntegrated mode and an explicit Application Insights connection string.");
    return 2;
}
if (authMode is not ("Jwt" or "ApiKey"))
{
    Console.Error.WriteLine("Unsupported HARNESS_AUTH_MODE. No authentication fallback is available.");
    return 2;
}
if (authMode == "ApiKey" && (apiKey is null || !Regex.IsMatch(apiKey, "\\A[0-9a-fA-F]{64}\\z")))
{
    Console.Error.WriteLine("ApiKey mode requires an explicit 256-bit hexadecimal HARNESS_API_KEY secret.");
    return 2;
}
if (authMode == "Jwt" && (!Uri.TryCreate(authority, UriKind.Absolute, out var issuer) || issuer.Scheme != "https"
    || string.IsNullOrWhiteSpace(audience)))
{
    Console.Error.WriteLine("An HTTPS HARNESS_AUTHORITY and HARNESS_AUTH_AUDIENCE are required. No authentication bypass is available.");
    return 2;
}
builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = 8192);
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow);
builder.Services.AddSingleton<HarnessTelemetry>();
builder.Services.AddSingleton<IRequestEvidence>(services => services.GetRequiredService<HarnessTelemetry>());
builder.Services.AddSingleton<ITutorialCatalog>(_ => new TutorialDocumentReader(CatalogPath()));
if (exportTelemetry)
    builder.Services.AddOpenTelemetry()
        .WithTracing(tracing => tracing.AddSource(HarnessTelemetry.ActivitySourceName))
        .UseAzureMonitor(options =>
            options.ConnectionString = builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]);
switch (mode)
{
    case "LocalDeterministic":
        builder.Services.AddSingleton<ITutorialSearch, LocalTutorialSearch>();
        break;
    case "AzureIntegrated":
        var endpoint = builder.Configuration["HARNESS_SEARCH_ENDPOINT"];
        var index = builder.Configuration["HARNESS_SEARCH_INDEX"];
        var clientId = builder.Configuration["HARNESS_MANAGED_IDENTITY_CLIENT_ID"];
        if (!Uri.TryCreate(endpoint, UriKind.Absolute, out var searchUri) || searchUri.Scheme != "https"
            || !searchUri.Host.EndsWith(".search.windows.net", StringComparison.OrdinalIgnoreCase)
            || string.IsNullOrWhiteSpace(index)
            || !double.TryParse(builder.Configuration["HARNESS_SEARCH_MINIMUM_SCORE"], CultureInfo.InvariantCulture, out var score)
            || !double.IsFinite(score) || score < 0 || !Guid.TryParse(clientId, out _))
        {
            Console.Error.WriteLine("AzureIntegrated requires an HTTPS Azure Search endpoint, index, explicit provider-specific minimum score and managed identity client ID. No local fallback was used.");
            return 2;
        }
        builder.Services.AddSingleton(new AzureTutorialSearch(new SearchClient(searchUri, index,
            new ManagedIdentityCredential(ManagedIdentityId.FromUserAssignedClientId(clientId))), score));
        builder.Services.AddSingleton<ITutorialSearch>(services => services.GetRequiredService<AzureTutorialSearch>());
        break;
    default:
        Console.Error.WriteLine($"Unsupported HARNESS_MODE '{mode}'. No local fallback was used.");
        return 2;
}
builder.Services.AddSingleton<TutorialSearchSpecialist>();
builder.Services.AddHttpContextAccessor();
builder.Services.AddMcpServer()
    .WithHttpTransport(options => options.SessionMode = HttpServerSessionMode.Stateless)
    .WithTools<TutorialMcpTools>();
if (authMode == "ApiKey")
{
    builder.Services.AddAuthentication(ApiKeyAuthenticationHandler.SchemeName)
        .AddScheme<ApiKeyOptions, ApiKeyAuthenticationHandler>(
            ApiKeyAuthenticationHandler.SchemeName, options => options.Key = apiKey!);
}
else
{
    builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
    {
        options.Authority = authority;
        options.Audience = audience;
        options.RequireHttpsMetadata = true;
        options.MapInboundClaims = false;
        options.IncludeErrorDetails = false;
        options.TokenValidationParameters.ClockSkew = TimeSpan.FromSeconds(30);
    });
}
builder.Services.AddAuthorization(options => options.AddPolicy("Tutorials.Search", policy =>
    policy.RequireAuthenticatedUser().RequireAssertion(context =>
        context.User.HasClaim("roles", "Tutorials.Search")
        || context.User.FindAll("scp").Any(claim =>
            claim.Value.Split(' ', StringSplitOptions.RemoveEmptyEntries).Contains("Tutorials.Search", StringComparer.Ordinal)))));
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.OnRejected = (context, _) =>
    {
        context.HttpContext.Response.Headers.RetryAfter = "60";
        return ValueTask.CompletedTask;
    };
    options.AddFixedWindowLimiter("tutorial-search", limiter =>
    {
        limiter.PermitLimit = 30;
        limiter.Window = TimeSpan.FromMinutes(1);
        limiter.QueueLimit = 0;
        limiter.QueueProcessingOrder = QueueProcessingOrder.OldestFirst;
    });
});

var app = builder.Build();
app.UseMiddleware<CorrelationMiddleware>();
app.UseMiddleware<ApiErrorMiddleware>();
app.UseStatusCodePages(async status =>
{
    var code = status.HttpContext.Response.StatusCode;
    var (name, message) = code switch
    {
        401 => ("unauthorized", authMode == "ApiKey" ? "A valid API key is required." : "A valid bearer token is required."),
        403 => ("forbidden", "Tutorials.Search is required."),
        404 => ("not_found", "The requested resource was not found."),
        413 => ("request_too_large", "The request exceeds the supported size."),
        429 => ("rate_limit", "The request limit was reached."),
        _ => ("request_failed", "The request could not be completed.")
    };
    await ApiErrorMiddleware.WriteErrorAsync(status.HttpContext, code, name, message);
});
app.UseAuthentication();
app.Use(async (context, next) =>
{
    var telemetry = context.RequestServices.GetRequiredService<HarnessTelemetry>();
    var id = (string)context.Items[CorrelationMiddleware.ItemKey]!;
    telemetry.Record(id, "auth.validate", context.User.Identity?.IsAuthenticated == true ? "authenticated" : "anonymous");
    await next(context);
    telemetry.Record(id, "authorization.check", context.Response.StatusCode is 401 or 403 ? "denied" : "completed");
});
app.UseAuthorization();
app.UseRateLimiter();
app.MapMcp("/mcp").RequireAuthorization("Tutorials.Search").RequireRateLimiting("tutorial-search");
app.MapGet("/health/live", () => Results.Ok(new { status = "live" }));
app.MapGet("/health/ready", async (ITutorialCatalog catalog, IServiceProvider services, HttpContext context) =>
{
    using var deadline = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);
    deadline.CancelAfter(TimeSpan.FromSeconds(5));
    if (mode == "AzureIntegrated")
        await services.GetRequiredService<AzureTutorialSearch>().CheckReadyAsync(deadline.Token);
    else
        await catalog.ReadAsync(deadline.Token);
    return Results.Ok(new { status = "ready" });
}).RequireAuthorization("Tutorials.Search");
app.MapGet("/api/capabilities", () => Results.Ok(new
    {
        capabilities = new[] { "buscar_tutoriales" },
        revision = Environment.GetEnvironmentVariable("CONTAINER_APP_REVISION") ?? "local",
        mode,
        authMode
    }))
    .RequireAuthorization("Tutorials.Search");
app.MapPost("/api/tutorials/search", async (HttpContext context, TutorialSearchSpecialist specialist) =>
{
    if (!context.Request.HasJsonContentType())
        throw new TutorialSearchException("validation_error", "Content-Type must be application/json.");
    using var reader = new StreamReader(context.Request.Body);
    var buffer = new char[8193];
    var length = await reader.ReadBlockAsync(buffer.AsMemory(), context.RequestAborted);
    if (length > 8192)
    {
        await ApiErrorMiddleware.WriteErrorAsync(context, 413, "request_too_large", "The request exceeds the supported size.");
        return;
    }
    var request = JsonSerializer.Deserialize<TutorialSearchRequest>(buffer.AsSpan(0, length),
        new JsonSerializerOptions(JsonSerializerDefaults.Web)
        {
            PropertyNameCaseInsensitive = false,
            UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
            MaxDepth = 8
        }) ?? throw new TutorialSearchException("validation_error", "A JSON request body is required.");
    using var deadline = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);
    deadline.CancelAfter(TimeSpan.FromSeconds(5));
    var response = await specialist.SearchAsync(request, (string)context.Items[CorrelationMiddleware.ItemKey]!, deadline.Token);
    await context.Response.WriteAsJsonAsync(response, context.RequestAborted);
}).RequireAuthorization("Tutorials.Search").RequireRateLimiting("tutorial-search");
app.MapGet("/openapi.json", () => Results.File(Path.Combine(AppContext.BaseDirectory, "openapi.json"), "application/json"));
await app.RunAsync();
return 0;

static string CatalogPath() => Path.Combine(AppContext.BaseDirectory, "knowledge", "tutorials", "catalog.json");

public partial class Program { }
