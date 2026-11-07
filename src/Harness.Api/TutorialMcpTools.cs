using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using Harness.Application;
using Harness.Contracts;
using ModelContextProtocol.Protocol;
using ModelContextProtocol.Server;

namespace Harness.Api;

[McpServerToolType]
public sealed class TutorialMcpTools(
    TutorialSearchSpecialist specialist,
    IHttpContextAccessor contexts,
    ILogger<TutorialMcpTools> logger)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [McpServerTool(Name = "buscar_tutoriales", ReadOnly = true, Destructive = false, Idempotent = true, OpenWorld = false)]
    [Description("Busca tutoriales Microsoft del catalogo de demostracion. Devuelve titulos, resumenes y fuentes sinteticas; no genera respuestas ni verifica enlaces externos.")]
    public async Task<CallToolResult> SearchAsync(
        RequestContext<CallToolRequestParams> request,
        [Description("Consulta del usuario, de 3 a 200 caracteres."), MinLength(3), MaxLength(200)] string query,
        CancellationToken cancellationToken,
        [Description("Numero maximo de tutoriales, de 1 a 5."), Range(1, 5)] int maxResults = 5,
        [Description("Audiencia de la demo: siempre community.")] string audience = "community")
    {
        var http = contexts.HttpContext ?? throw new InvalidOperationException("MCP search requires an HTTP request.");
        var correlationId = (string)http.Items[CorrelationMiddleware.ItemKey]!;
        try
        {
            if (request.Params?.Arguments?.Keys.Any(name => name is not ("query" or "maxResults" or "audience")) == true)
                throw new TutorialSearchException("validation_error", "Only query, maxResults and audience are supported.");
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, http.RequestAborted);
            deadline.CancelAfter(TimeSpan.FromSeconds(5));
            var result = await specialist.SearchAsync(new(query, maxResults, audience), correlationId, deadline.Token);
            return Result(result, false);
        }
        catch (TutorialSearchException exception)
        {
            return Result(new ApiError(exception.Code, exception.Message, correlationId), true);
        }
        catch (OperationCanceledException) when (!http.RequestAborted.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
        {
            return Result(new ApiError("request_timeout", "The request did not complete before its deadline.", correlationId), true);
        }
        catch (IOException exception)
        {
            logger.LogError("MCP search storage failure: {FailureType}", exception.GetType().Name);
            return Result(new ApiError("search_unavailable", "The search dependency is unavailable.", correlationId), true);
        }
    }

    private static CallToolResult Result<T>(T value, bool isError)
    {
        var json = JsonSerializer.SerializeToElement(value, JsonOptions);
        return new CallToolResult
        {
            IsError = isError,
            StructuredContent = json,
            Content = [new TextContentBlock { Text = json.GetRawText() }]
        };
    }
}
