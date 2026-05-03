import Foundation
import VecturaKit

/// SQLite-backed Vectura storage provider with HNSW candidate search.
///
/// Version 0.1 keeps the HNSW graph in memory and rebuilds it from SQLite on open.
/// Documents remain disk-backed through SQLite.
public actor HNSWStorageProvider: IndexedVecturaStorage {
  public let directoryURL: URL
  public let dimension: Int
  public let config: HNSWConfig

  private let store: SQLiteDocumentStore
  private var index: HNSWIndex

  public init(
    directoryURL: URL,
    dimension: Int,
    config: HNSWConfig = .default
  ) throws {
    guard dimension > 0 else {
      throw HNSWStorageError.invalidConfiguration("dimension must be greater than 0")
    }

    self.directoryURL = directoryURL
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

    let documents = try store.loadActiveDocuments()
    try index.rebuild(documents: documents)
  }

  public var stats: HNSWIndexStats {
    index.stats
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
    try index.add(documentID: document.id, vector: document.embedding)
  }

  public func saveDocuments(_ documents: [VecturaDocument]) async throws {
    try documents.forEach(validate)
    try store.saveDocuments(documents)
    for document in documents {
      try index.add(documentID: document.id, vector: document.embedding)
    }
  }

  public func deleteDocument(withID id: UUID) async throws {
    try store.deleteDocument(id: id)
    index.markDeleted(documentID: id)
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
    guard queryEmbedding.count == dimension else {
      throw HNSWStorageError.invalidDimension(expected: dimension, actual: queryEmbedding.count)
    }

    let limit = max(topK, prefilterSize)
    let candidates = try index.search(query: queryEmbedding, limit: limit, efSearch: max(limit, config.efSearch))
    return candidates
  }

  private func validate(_ document: VecturaDocument) throws {
    guard document.embedding.count == dimension else {
      throw HNSWStorageError.invalidDimension(expected: dimension, actual: document.embedding.count)
    }
  }
}
