using Harness.Application;
using Harness.Domain;
using Harness.Infrastructure.Search;

namespace Harness.ArchitectureTests;

public sealed class LayerDependenciesTests
{
    [Fact]
    public void DomainAndApplicationHaveNoTransportOrCloudDependencies()
    {
        var domain = typeof(Tutorial).Assembly.GetReferencedAssemblies().Select(assembly => assembly.Name).ToArray();
        Assert.DoesNotContain(domain, name => name is not null &&
            (name.StartsWith("Azure", StringComparison.Ordinal) || name.StartsWith("Microsoft.AspNetCore", StringComparison.Ordinal)));
        var application = typeof(TutorialSearchSpecialist).Assembly.GetReferencedAssemblies().Select(assembly => assembly.Name).ToArray();
        Assert.DoesNotContain("Harness.Api", application);
        Assert.DoesNotContain("Harness.Infrastructure", application);
        Assert.DoesNotContain(application, name => name?.StartsWith("Azure", StringComparison.Ordinal) == true);
        Assert.DoesNotContain(typeof(LocalTutorialSearch).Assembly.GetReferencedAssemblies(),
            assembly => assembly.Name?.StartsWith("Microsoft.AspNetCore", StringComparison.Ordinal) == true);
    }
}
