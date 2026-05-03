/// Runtime statistics for an HNSW storage provider.
public struct HNSWIndexStats: Equatable, Sendable {
  public let dimension: Int
  public let documentCount: Int
  public let activeNodeCount: Int
  public let deletedNodeCount: Int
  public let maxLayer: Int
  public let snapshotBytes: Int?

  public init(
    dimension: Int,
    documentCount: Int,
    activeNodeCount: Int,
    deletedNodeCount: Int,
    maxLayer: Int,
    snapshotBytes: Int? = nil
  ) {
    self.dimension = dimension
    self.documentCount = documentCount
    self.activeNodeCount = activeNodeCount
    self.deletedNodeCount = deletedNodeCount
    self.maxLayer = maxLayer
    self.snapshotBytes = snapshotBytes
  }
}
