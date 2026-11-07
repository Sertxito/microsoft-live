using Harness.Domain;

namespace Harness.Application.Ports;

public interface ITutorialCatalog
{
    Task<IReadOnlyList<Tutorial>> ReadAsync(CancellationToken cancellationToken);
}
