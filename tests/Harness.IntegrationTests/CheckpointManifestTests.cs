using System.Diagnostics;

namespace Harness.IntegrationTests;

public sealed class CheckpointManifestTests
{
    [Fact]
    public async Task MissingGitReferenceFailsWithoutCreatingCheckpoint()
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root is not null && !File.Exists(Path.Combine(root.FullName, "Harness.sln"))) root = root.Parent;
        Assert.NotNull(root);
        var manifest = Path.Combine(Path.GetTempPath(), $"harness-checkpoint-{Guid.NewGuid():N}.json");
        try
        {
            await File.WriteAllTextAsync(manifest, """{"tag":"nonexistent-demo-checkpoint","commit":"0000000000000000000000000000000000000000","files":[]}""");
            var start = new ProcessStartInfo("pwsh") { RedirectStandardOutput = true, RedirectStandardError = true };
            foreach (var argument in new[] { "-NoProfile", "-File", Path.Combine(root.FullName, "scripts", "verify-checkpoint.ps1"), "-Manifest", manifest })
                start.ArgumentList.Add(argument);
            using var child = Process.Start(start) ?? throw new InvalidOperationException("PowerShell did not start.");
            var stdout = child.StandardOutput.ReadToEndAsync();
            var stderr = child.StandardError.ReadToEndAsync();
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            try { await child.WaitForExitAsync(deadline.Token); }
            catch (OperationCanceledException) { child.Kill(entireProcessTree: true); throw; }
            Assert.NotEqual(0, child.ExitCode);
            Assert.Contains("Checkpoint tag is absent", (await stdout) + (await stderr));
        }
        finally { if (File.Exists(manifest)) File.Delete(manifest); }
    }
}
