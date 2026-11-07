using System.Text.Json;
using Harness.Application;
using Harness.Contracts;

namespace Harness.Api;

public sealed class ApiErrorMiddleware(RequestDelegate next, ILogger<ApiErrorMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
        {
            throw;
        }
        catch (TutorialSearchException exception)
        {
            await WriteErrorAsync(
                context,
                exception.Code switch { "validation_error" => 400, "search_unavailable" => 503, "invalid_search_response" => 503, _ => 500 },
                exception.Code,
                exception.Message);
        }
        catch (JsonException)
        {
            await WriteErrorAsync(
                context,
                StatusCodes.Status400BadRequest,
                "validation_error",
                "The request body is not valid for this operation.");
        }
        catch (BadHttpRequestException exception)
        {
            await WriteErrorAsync(context, exception.StatusCode, "validation_error", "The request could not be read.");
        }
        catch (IOException exception)
        {
            logger.LogError("Search storage failure: {FailureType}", exception.GetType().Name);
            await WriteErrorAsync(context, 503, "search_unavailable", "The search dependency is unavailable.");
        }
        catch (OperationCanceledException)
        {
            await WriteErrorAsync(
                context,
                StatusCodes.Status408RequestTimeout,
                "request_timeout",
                "The request did not complete before its deadline.");
        }
        catch (Exception exception)
        {
            logger.LogError("Unhandled request failure: {FailureType}", exception.GetType().Name);
            await WriteErrorAsync(
                context,
                StatusCodes.Status500InternalServerError,
                "internal_error",
                "The request could not be completed.");
        }
    }

    public static async Task WriteErrorAsync(
        HttpContext context,
        int statusCode,
        string code,
        string message)
    {
        if (context.Response.HasStarted)
        {
            throw new InvalidOperationException("The response has already started.");
        }

        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "application/json";
        var correlationId = context.Items.TryGetValue(CorrelationMiddleware.ItemKey, out var value)
            ? (string)value!
            : Guid.NewGuid().ToString("D");
        await JsonSerializer.SerializeAsync(
            context.Response.Body,
            new ApiError(code, message, correlationId),
            new JsonSerializerOptions(JsonSerializerDefaults.Web),
            cancellationToken: context.RequestAborted);
    }
}
