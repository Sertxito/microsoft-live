namespace Harness.Application;

public sealed class TutorialSearchException(string code, string message, Exception? innerException = null)
    : Exception(message, innerException)
{
    public string Code { get; } = code;
}
