/// Startup behavior for restoring the HNSW graph.
public enum HNSWRecoveryPolicy: Equatable, Sendable {
  /// Ignore snapshots and rebuild the graph from active SQLite documents.
  case rebuildFromDocuments

  /// Load the snapshot if it exists, otherwise rebuild from SQLite documents.
  case loadSnapshotIfAvailable

  /// Load the snapshot if it exists, then rebuild if it does not match active SQLite documents.
  case validateSnapshotIfAvailable
}

/// Describes how a storage provider recovered its index during initialization.
public struct HNSWRecoveryReport: Equatable, Sendable {
  public let policy: HNSWRecoveryPolicy
  public let loadedSnapshot: Bool
  public let rebuiltFromDocuments: Bool
  public let reason: String?

  public init(
    policy: HNSWRecoveryPolicy,
    loadedSnapshot: Bool,
    rebuiltFromDocuments: Bool,
    reason: String?
  ) {
    self.policy = policy
    self.loadedSnapshot = loadedSnapshot
    self.rebuiltFromDocuments = rebuiltFromDocuments
    self.reason = reason
  }
}
