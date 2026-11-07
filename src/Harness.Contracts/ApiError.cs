namespace Harness.Contracts;

public sealed record ApiError(string Code, string Message, string CorrelationId);
