using System.Diagnostics;

namespace Harness.IntegrationTests;

public sealed class LocalScriptSafetyTests
{
    [Fact]
    public async Task RemoteSmokeRequiresExplicitAuthorizationWithoutMakingNetworkCalls()
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root is not null && !File.Exists(Path.Combine(root.FullName, "Harness.sln"))) root = root.Parent;
        Assert.NotNull(root);
        var start = new ProcessStartInfo("pwsh") { RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "-NoProfile", "-File", Path.Combine(root.FullName, "scripts", "smoke-test.ps1"),
            "-BaseUri", "https://example.invalid/", "-BearerToken", "test-not-a-token" })
            start.ArgumentList.Add(argument);
        using var child = Process.Start(start) ?? throw new InvalidOperationException("PowerShell did not start.");
        var stdout = child.StandardOutput.ReadToEndAsync();
        var stderr = child.StandardError.ReadToEndAsync();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        try { await child.WaitForExitAsync(deadline.Token); }
        catch (OperationCanceledException) { child.Kill(entireProcessTree: true); throw; }
        Assert.NotEqual(0, child.ExitCode);
        Assert.Contains("Remote calls require explicit target authorization", (await stdout) + (await stderr));
    }
}
