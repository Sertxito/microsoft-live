using System.Text.Json;

namespace Harness.ContractTests;

public sealed class DemoArtifactSafetyTests
{
    [Fact]
    public void DemoCredentialsAndOperationalActionsAreNotPersisted()
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root is not null && !File.Exists(Path.Combine(root.FullName, "Harness.sln"))) root = root.Parent;
        Assert.NotNull(root);
        foreach (var name in new[] { "tutorial-search.postman_collection.json", "tutorial-search-api-key.postman_collection.json", "tutorial-search-mcp.postman_collection.json" })
        {
            using var collection = JsonDocument.Parse(File.ReadAllText(Path.Combine(root.FullName, "demo", "postman", name)));
            Assert.All(collection.RootElement.GetProperty("variable").EnumerateArray(),
                variable => Assert.Equal("", variable.GetProperty("value").GetString()));
        }
        Assert.False(File.Exists(Path.Combine(root.FullName, "scripts", "cleanup.ps1")));
        var productionFiles = Directory.EnumerateFiles(Path.Combine(root.FullName, "src"), "*.cs", SearchOption.AllDirectories)
            .Where(file => !file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal));
        Assert.All(productionFiles, file => Assert.DoesNotContain("issuer.test", File.ReadAllText(file)));
    }
}
