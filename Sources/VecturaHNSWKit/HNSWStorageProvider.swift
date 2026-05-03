import Foundation
import VecturaKit

/// SQLite-backed Vectura storage provider with HNSW candidate search.
///
/// Documents are disk-backed through SQLite. The HNSW graph is kept in memory
/// for fast candidate lookup and can be restored from a validated snapshot or
/// rebuilt from SQLite when needed.
public actor HNSWStorageProvider: IndexedVecturaStorage {
  public let directoryURL: URL
  public let snapshotURL: URL
  public let dimension: Int
  public let config: HNSWConfig
  public let recoveryReport: HNSWRecoveryReport

  private let store: SQLiteDocumentStore
  private var index: HNSWIndex

  public init(
    directoryURL: URL,
    dimension: Int,
    config: HNSWConfig = .default,
    recoveryPolicy: HNSWRecoveryPolicy = .validateSnapshotIfAvailable
  ) throws {
    guard dimension > 0 else {
      throw HNSWStorageError.invalidConfiguration("dimension must be greater than 0")
    }

    self.directoryURL = directoryURL
    self.snapshotURL = directoryURL.appendingPathComponent("hnsw-index.vkhnsw")
    self.dimension = dimension
    self.config = config

    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )

    self.store = try SQLiteDocumentStore(
      databaseURL: directoryURL.appendingPathComponent("documents.sqlite3"),
      dimension: dimension
    )
    self.index = try HNSWIndex(dimension: dimension, config: config)

    self.recoveryReport = try Self.recoverIndex(
      index: index,
      store: store,
      snapshotURL: snapshotURL,
      policy: recoveryPolicy
    )
  }

  public var stats: HNSWIndexStats {
    let snapshotBytes = (try? FileManager.default.attributesOfItem(atPath: snapshotURL.path)[.size] as? NSNumber)?
      .intValue
    let current = index.stats
    return HNSWIndexStats(
      dimension: current.dimension,
      documentCount: current.documentCount,
      activeNodeCount: current.activeNodeCount,
      deletedNodeCount: current.deletedNodeCount,
      maxLayer: current.maxLayer,
      snapshotBytes: snapshotBytes
    )
  }

  /// Persists the current in-memory HNSW graph as a binary snapshot.
  public func saveIndexSnapshot() async throws {
    let snapshot = index.snapshot(documentRevision: try store.currentDocumentRevision())
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(snapshot)
    try data.write(to: snapshotURL, options: .atomic)
  }

  /// Rebuilds the in-memory graph from active SQLite documents.
  public func rebuildIndex() async throws {
    let documents = try store.loadActiveDocuments()
    try index.rebuild(documents: documents)
  }

  /// Rebuilds the graph from active documents and persists a fresh snapshot.
  public func compactIndex() async throws {
    try await rebuildIndex()
    try await saveIndexSnapshot()
  }

  private static func recoverIndex(
    index: HNSWIndex,
    store: SQLiteDocumentStore,
    snapshotURL: URL,
    policy: HNSWRecoveryPolicy
  ) throws -> HNSWRecoveryReport {
    switch policy {
    case .rebuildFromDocuments:
      let documents = try store.loadActiveDocuments()
      try index.rebuild(documents: documents)
      return HNSWRecoveryReport(
        policy: policy,
        loadedSnapshot: false,
        rebuiltFromDocuments: true,
        reason: "Recovery policy requested rebuild"
      )

    case .loadSnapshotIfAvailable:
      guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
        let documents = try store.loadActiveDocuments()
        try index.rebuild(documents: documents)
        return HNSWRecoveryReport(
          policy: policy,
          loadedSnapshot: false,
          rebuiltFromDocuments: true,
          reason: "Snapshot not found"
        )
      }
      _ = try loadSnapshot(into: index, snapshotURL: snapshotURL)
      return HNSWRecoveryReport(
        policy: policy,
        loadedSnapshot: true,
        rebuiltFromDocuments: false,
        reason: nil
      )

    case .validateSnapshotIfAvailable:
      guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
        let documents = try store.loadActiveDocuments()
        try index.rebuild(documents: documents)
        return HNSWRecoveryReport(
          policy: policy,
          loadedSnapshot: false,
          rebuiltFromDocuments: true,
          reason: "Snapshot not found"
        )
      }

      let snapshot = try loadSnapshot(into: index, snapshotURL: snapshotURL)
      let documents = try store.loadActiveDocuments()
      let currentRevision = try store.currentDocumentRevision()
      guard snapshot.documentRevision == currentRevision else {
        try index.rebuild(documents: documents)
        return HNSWRecoveryReport(
          policy: policy,
          loadedSnapshot: true,
          rebuiltFromDocuments: true,
          reason: "Snapshot revision did not match SQLite"
        )
      }

      let activeIDs = Set(documents.map(\.id))
      guard index.activeDocumentIDs == activeIDs else {
        try index.rebuild(documents: documents)
        return HNSWRecoveryReport(
          policy: policy,
          loadedSnapshot: true,
          rebuiltFromDocuments: true,
          reason: "Snapshot document IDs did not match SQLite"
        )
      }

      return HNSWRecoveryReport(
        policy: policy,
        loadedSnapshot: true,
        rebuiltFromDocuments: false,
        reason: nil
      )
    }
  }

  private static func loadSnapshot(into index: HNSWIndex, snapshotURL: URL) throws -> HNSWIndexSnapshot {
    let data = try Data(contentsOf: snapshotURL)
    let snapshot = try PropertyListDecoder().decode(HNSWIndexSnapshot.self, from: data)
    try index.restore(from: snapshot)
    return snapshot
  }

  public func createStorageDirectoryIfNeeded() async throws {
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
  }

  public func loadDocuments() async throws -> [VecturaDocument] {
    try store.loadActiveDocuments()
  }

  public func saveDocument(_ document: VecturaDocument) async throws {
    try validate(document)
    try store.saveDocument(document)
    do {
      try index.add(documentID: document.id, vector: document.embedding)
      try await compactIndexIfNeeded()
    } catch {
      try? index.rebuild(documents: store.loadActiveDocuments())
      throw error
    }
  }

  public func saveDocuments(_ documents: [VecturaDocument]) async throws {
    try documents.forEach(validate)
    try store.saveDocuments(documents)
    do {
      index.reserveCapacity(additionalNodeCount: documents.count)
      for document in documents {
        try index.add(documentID: document.id, vector: document.embedding)
      }
      try await compactIndexIfNeeded()
    } catch {
      try? index.rebuild(documents: store.loadActiveDocuments())
      throw error
    }
  }

  public func deleteDocument(withID id: UUID) async throws {
    try store.deleteDocument(id: id)
    index.markDeleted(documentID: id)
    try await compactIndexIfNeeded()
  }

  public func updateDocument(_ document: VecturaDocument) async throws {
    try await saveDocument(document)
  }

  public func getTotalDocumentCount() async throws -> Int {
    try store.countActiveDocuments()
  }

  public func getDocument(id: UUID) async throws -> VecturaDocument? {
    try store.loadDocument(id: id)
  }

  public func documentExists(id: UUID) async throws -> Bool {
    try store.documentExists(id: id)
  }

  public func loadDocuments(offset: Int, limit: Int) async throws -> [VecturaDocument] {
    try store.loadDocuments(offset: offset, limit: limit)
  }

  public func loadDocuments(ids: [UUID]) async throws -> [UUID: VecturaDocument] {
    try store.loadDocuments(ids: ids)
  }

  public func searchVectorCandidates(
    queryEmbedding: [Float],
    topK: Int,
    prefilterSize: Int
  ) async throws -> [UUID]? {
    if shouldUseExactCandidateSearch {
      return try index.exactSearch(
        query: queryEmbedding,
        limit: topK
      )
    }

    return try await searchDocumentIDs(
      queryEmbedding: queryEmbedding,
      limit: max(topK, prefilterSize)
    )
  }

  /// Searches the HNSW graph directly and returns document IDs without loading documents.
  ///
  /// This is useful for measuring pure index lookup cost or for callers that want
  /// to perform their own candidate loading and rescoring.
  public func searchDocumentIDs(
    queryEmbedding: [Float],
    limit: Int
  ) async throws -> [UUID] {
    guard queryEmbedding.count == dimension else {
      throw HNSWStorageError.invalidDimension(expected: dimension, actual: queryEmbedding.count)
    }

    return try index.search(query: queryEmbedding, limit: limit, efSearch: max(limit, config.efSearch))
  }

  private var shouldUseExactCandidateSearch: Bool {
    guard config.exactSearchThreshold > 0 else {
      return false
    }
    return index.stats.documentCount <= config.exactSearchThreshold
  }

  private func compactIndexIfNeeded() async throws {
    let stats = index.stats
    guard stats.deletedNodeCount >= config.automaticCompactionMinimumDeletedCount else {
      return
    }

    let totalNodeCount = stats.activeNodeCount + stats.deletedNodeCount
    guard totalNodeCount > 0 else {
      return
    }

    let deletedRatio = Double(stats.deletedNodeCount) / Double(totalNodeCount)
    guard deletedRatio >= config.automaticCompactionDeletedRatio else {
      return
    }

    try await compactIndex()
  }

  private func validate(_ document: VecturaDocument) throws {
    guard document.embedding.count == dimension else {
      throw HNSWStorageError.invalidDimension(expected: dimension, actual: document.embedding.count)
    }
  }
}
