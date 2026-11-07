using System.Diagnostics;

namespace Harness.IntegrationTests;

public sealed class AzureOperationSafetyTests
{
    [Theory]
    [InlineData("EntraGate")]
    [InlineData("NetworkGate")]
    [InlineData("NetworkPreview")]
    [InlineData("NetworkApply")]
    [InlineData("NetworkMissingTag")]
    [InlineData("NetworkDenied")]
    [InlineData("FoundationGate")]
    [InlineData("LoaderGate")]
    [InlineData("BuildGate")]
    [InlineData("CandidateGate")]
    [InlineData("CandidateConnectorPreserved")]
    [InlineData("CandidateConnectorDrift")]
    [InlineData("RbacGate")]
    [InlineData("TrafficGate")]
    [InlineData("Promote")]
    [InlineData("Rollback")]
    [InlineData("FailedSmoke")]
    [InlineData("WrongRevision")]
    [InlineData("StaleTraffic")]
    [InlineData("NoPrevious")]
    [InlineData("ForbiddenBypass")]
    [InlineData("Load")]
    [InlineData("LoadNew")]
    [InlineData("LoadRerun")]
    [InlineData("SchemaMismatch")]
    [InlineData("WrongLoader")]
    [InlineData("BatchFailure")]
    [InlineData("CatalogOverflow")]
    [InlineData("KeyPromote")]
    [InlineData("McpPromote")]
    [InlineData("McpPromoteRelativeState")]
    [InlineData("McpFailedSmoke")]
    [InlineData("KeyWrongMode")]
    [InlineData("KeyBypass")]
    public async Task OperationalGatesUseNoRealAzureOrHttp(string scenario)
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root is not null && !File.Exists(Path.Combine(root.FullName, "Harness.sln"))) root = root.Parent;
        Assert.NotNull(root);
        var start = new ProcessStartInfo("pwsh") { RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "-NoProfile", "-File", Path.Combine(root.FullName,
            "tests", "fixtures", "azure-operation-safety.ps1"), "-Scenario", scenario })
            start.ArgumentList.Add(argument);
        using var child = Process.Start(start) ?? throw new InvalidOperationException("PowerShell did not start.");
        var stdout = child.StandardOutput.ReadToEndAsync();
        var stderr = child.StandardError.ReadToEndAsync();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        try { await child.WaitForExitAsync(deadline.Token); }
        catch (OperationCanceledException) { child.Kill(entireProcessTree: true); throw; }
        Assert.True(child.ExitCode == 0, (await stdout) + (await stderr));
        Assert.Contains("Fixture passed", await stdout);
    }
}
