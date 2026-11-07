using System.Diagnostics;

namespace Harness.IntegrationTests;

public sealed class AzureStartupSafetyTests
{
    [Theory]
    [InlineData("LocalDeterministic", "invalid", "Telemetry export requires")]
    [InlineData("LocalDeterministic", "true", "Telemetry export requires")]
    [InlineData("AzureIntegrated", "true", "Telemetry export requires")]
    [InlineData("AzureIntegrated", "false", "managed identity client ID")]
    public async Task InvalidCloudConfigurationFailsBeforeOpeningServer(string mode, string export, string expected)
    {
        var start = new ProcessStartInfo("dotnet") { RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[]
        {
            typeof(Program).Assembly.Location, $"--HARNESS_MODE={mode}", $"--HARNESS_TELEMETRY_EXPORT={export}",
            "--HARNESS_AUTHORITY=https://issuer.test", "--HARNESS_AUTH_AUDIENCE=fixture",
            "--APPLICATIONINSIGHTS_CONNECTION_STRING=", "--HARNESS_MANAGED_IDENTITY_CLIENT_ID=",
            "--HARNESS_SEARCH_ENDPOINT=https://fixture.search.windows.net", "--HARNESS_SEARCH_INDEX=tutorials",
            "--HARNESS_SEARCH_MINIMUM_SCORE=0"
        })
            start.ArgumentList.Add(argument);
        using var child = Process.Start(start) ?? throw new InvalidOperationException("API process did not start.");
        var stdout = child.StandardOutput.ReadToEndAsync();
        var stderr = child.StandardError.ReadToEndAsync();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        try { await child.WaitForExitAsync(deadline.Token); }
        catch (OperationCanceledException) { child.Kill(entireProcessTree: true); throw; }
        Assert.Equal(2, child.ExitCode);
        Assert.Contains(expected, (await stdout) + (await stderr));
    }
}
