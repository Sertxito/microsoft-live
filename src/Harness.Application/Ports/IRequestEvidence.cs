namespace Harness.Application.Ports;

public interface IRequestEvidence
{
    void Record(string correlationId, string stage, string outcome, long durationMs = 0, int? resultCount = null);
}
