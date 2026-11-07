using System.Diagnostics;

namespace Harness.IntegrationTests;

public sealed class ApiKeyStartupTests
{
    [Theory]
    [InlineData("ApiKey", "")]
    [InlineData("ApiKey", "short")]
    [InlineData("ApiKey", "not-a-256-bit-hex-key")]
    [InlineData("Anonymous", "")]
    public async Task InvalidKeyConfigurationFailsBeforeOpeningServer(string mode, string key)
    {
        var start = new ProcessStartInfo("dotnet") { RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[]
        {
            typeof(Program).Assembly.Location, $"--HARNESS_AUTH_MODE={mode}", $"--HARNESS_API_KEY={key}",
            "--HARNESS_MODE=LocalDeterministic", "--HARNESS_TELEMETRY_EXPORT=false"
        })
            start.ArgumentList.Add(argument);
        using var child = Process.Start(start) ?? throw new InvalidOperationException("API process did not start.");
        var stdout = child.StandardOutput.ReadToEndAsync();
        var stderr = child.StandardError.ReadToEndAsync();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        try { await child.WaitForExitAsync(deadline.Token); }
        catch (OperationCanceledException) { child.Kill(entireProcessTree: true); throw; }
        Assert.Equal(2, child.ExitCode);
        Assert.Contains(mode == "ApiKey" ? "256-bit hexadecimal" : "Unsupported HARNESS_AUTH_MODE", (await stdout) + (await stderr));
    }
}
