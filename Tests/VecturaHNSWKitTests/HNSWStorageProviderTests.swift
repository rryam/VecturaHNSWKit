import Foundation
import SQLite3
import Testing
import VecturaHNSWKit
import VecturaKit

@Suite("HNSWStorageProvider")
struct HNSWStorageProviderTests {
  @Test("stores documents in SQLite and returns HNSW candidates")
  func storesDocumentsAndSearchesCandidates() async throws {
    let directory = try temporaryDirectory()
    let storage = try HNSWStorageProvider(directoryURL: directory, dimension: 3)

    let apple = VecturaDocument(text: "apple", embedding: [1, 0, 0])
    let banana = VecturaDocument(text: "banana", embedding: [0, 1, 0])
    let car = VecturaDocument(text: "car", embedding: [0, 0, 1])

    try await storage.saveDocuments([apple, banana, car])

    let count = try await storage.getTotalDocumentCount()
    #expect(count == 3)

    let candidates = try await storage.searchVectorCandidates(
      queryEmbedding: [1, 0, 0],
      topK: 1,
      prefilterSize: 2
    )

    #expect(candidates?.first == apple.id)
  }

  @Test("plugs into VecturaKit indexed vector search")
  func plugsIntoVecturaKitIndexedSearch() async throws {
    let directory = try temporaryDirectory()
    let storage = try HNSWStorageProvider(
      directoryURL: directory.appendingPathComponent("hnsw"),
      dimension: 3
    )
    let embedder = DictionaryEmbedder(
      dimension: 3,
      embeddings: [
        "apple": [1, 0, 0],
        "banana": [0, 1, 0],
        "car": [0, 0, 1],
      ]
    )
    let config = try VecturaConfig(
      name: "hnsw-test",
      directoryURL: directory.appendingPathComponent("vectura"),
      dimension: 3,
      memoryStrategy: .indexed(candidateMultiplier: 4)
    )

    let vectura = try await VecturaKit(
      config: config,
      embedder: embedder,
      storageProvider: storage
    )

    _ = try await vectura.addDocuments(texts: ["apple", "banana", "car"])

    let results = try await vectura.search(
      query: .vector([1, 0, 0]),
      numResults: 1,
      threshold: nil
    )

    #expect(results.first?.text == "apple")
  }

  @Test("searchText returns ranked SQLite text results")
  func searchTextReturnsRankedSQLiteTextResults() async throws {
    let directory = try temporaryDirectory()
    let storage = try HNSWStorageProvider(directoryURL: directory, dimension: 3)
    let appleRecipe = VecturaDocument(text: "apple pie recipe", embedding: [1, 0, 0])
    let appleLaptop = VecturaDocument(text: "apple laptop", embedding: [0, 1, 0])
    let banana = VecturaDocument(text: "banana smoothie", embedding: [0, 0, 1])

    try await storage.saveDocuments([appleRecipe, appleLaptop, banana])

    let results = try await storage.searchText(query: "apple recipe", topK: 2) ?? []

    #expect(results.map(\.id) == [appleRecipe.id, appleLaptop.id])
    #expect(results.allSatisfy { $0.score > 0 })

    try await storage.deleteDocument(withID: appleRecipe.id)

    let afterDelete = try await storage.searchText(query: "apple recipe", topK: 2) ?? []
    #expect(afterDelete.map(\.id) == [appleLaptop.id])
  }

  @Test("plugs into VecturaKit indexed text search")
  func plugsIntoVecturaKitIndexedTextSearch() async throws {
    let directory = try temporaryDirectory()
    let provider = try HNSWStorageProvider(
      directoryURL: directory.appendingPathComponent("hnsw"),
      dimension: 3
    )
    let storage = TextSearchSpyStorage(wrapping: provider)
    let embedder = DictionaryEmbedder(
      dimension: 3,
      embeddings: [
        "apple pie recipe": [1, 0, 0],
        "apple laptop": [0, 1, 0],
        "banana smoothie": [0, 0, 1],
        "apple recipe": [1, 0, 0],
      ]
    )
    let config = try VecturaConfig(
      name: "hnsw-text-test",
      directoryURL: directory.appendingPathComponent("vectura"),
      dimension: 3,
      searchOptions: .init(hybridWeight: 0),
      memoryStrategy: .indexed(candidateMultiplier: 4)
    )

    let vectura = try await VecturaKit(
      config: config,
      embedder: embedder,
      storageProvider: storage
    )

    _ = try await vectura.addDocuments(texts: ["apple pie recipe", "apple laptop", "banana smoothie"])

    let results = try await vectura.search(
      query: .text("apple recipe"),
      numResults: 1,
      threshold: nil
    )

    #expect(results.first?.text == "apple pie recipe")

    // Guard against the storage hook silently unbinding (e.g. a VecturaKit
    // resolution without the searchText requirement): the result must come
    // from the storage-level text index, not the in-memory BM25 fallback.
    let searchTextCalls = await storage.searchTextCallCount
    #expect(searchTextCalls > 0)
  }

  @Test("delete removes active document from candidate results")
  func deleteRemovesActiveDocumentFromCandidates() async throws {
    let directory = try temporaryDirectory()
    let storage = try HNSWStorageProvider(directoryURL: directory, dimension: 3)

    let apple = VecturaDocument(text: "apple", embedding: [1, 0, 0])
    let banana = VecturaDocument(text: "banana", embedding: [0.95, 0.05, 0])
    try await storage.saveDocuments([apple, banana])
    try await storage.deleteDocument(withID: apple.id)

    let candidates = try await storage.searchVectorCandidates(
      queryEmbedding: [1, 0, 0],
      topK: 1,
      prefilterSize: 2
    )

    #expect(candidates?.first == banana.id)
    #expect(try await storage.documentExists(id: apple.id) == false)
  }

  @Test("loads requested documents in batches")
  func loadsRequestedDocumentsInBatches() async throws {
    let directory = try temporaryDirectory()
    let storage = try HNSWStorageProvider(directoryURL: directory, dimension: 3)

    let documents = (0..<520).map { index in
      VecturaDocument(
        text: "doc-\(index)",
        embedding: [1, Float(index % 7), Float(index % 3)]
      )
    }
    try await storage.saveDocuments(documents)

    let loaded = try await storage.loadDocuments(ids: documents.map(\.id))

    #expect(loaded.count == documents.count)
    #expect(loaded[documents[0].id]?.text == "doc-0")
    #expect(loaded[documents[519].id]?.text == "doc-519")
  }

  @Test("snapshot can be saved and loaded on reopen")
  func snapshotCanBeSavedAndLoadedOnReopen() async throws {
    let directory = try temporaryDirectory()
    let storage = try HNSWStorageProvider(directoryURL: directory, dimension: 3)
    let apple = VecturaDocument(text: "apple", embedding: [1, 0, 0])
    let banana = VecturaDocument(text: "banana", embedding: [0, 1, 0])

    try await storage.saveDocuments([apple, banana])
    try await storage.saveIndexSnapshot()

    let reopened = try HNSWStorageProvider(directoryURL: directory, dimension: 3)
    let candidates = try await reopened.searchVectorCandidates(
      queryEmbedding: [1, 0, 0],
      topK: 1,
      prefilterSize: 2
    )
    let stats = await reopened.stats

    #expect(candidates?.first == apple.id)
    #expect((stats.snapshotBytes ?? 0) > 0)
  }

  @Test("compact rebuilds graph without deleted nodes")
  func compactRebuildsGraphWithoutDeletedNodes() async throws {
    let directory = try temporaryDirectory()
    let storage = try HNSWStorageProvider(directoryURL: directory, dimension: 3)
    let apple = VecturaDocument(text: "apple", embedding: [1, 0, 0])
    let banana = VecturaDocument(text: "banana", embedding: [0, 1, 0])

    try await storage.saveDocuments([apple, banana])
    try await storage.deleteDocument(withID: apple.id)

    let beforeCompact = await storage.stats
    try await storage.compactIndex()
    let afterCompact = await storage.stats

    #expect(beforeCompact.deletedNodeCount == 1)
    #expect(afterCompact.deletedNodeCount == 0)
    #expect(afterCompact.activeNodeCount == 1)
    #expect((afterCompact.snapshotBytes ?? 0) > 0)
  }

  @Test("failed rebuild preserves existing in-memory index")
  func failedRebuildPreservesExistingInMemoryIndex() async throws {
    let directory = try temporaryDirectory()
    let config = try HNSWConfig(exactSearchThreshold: 0)
    let storage = try HNSWStorageProvider(directoryURL: directory, dimension: 3, config: config)
    let apple = VecturaDocument(text: "apple", embedding: [1, 0, 0])
    let banana = VecturaDocument(text: "banana", embedding: [0, 1, 0])

    try await storage.saveDocuments([apple, banana])
    try corruptEmbedding(for: banana.id, in: directory, embedding: [0, 1])

    await #expect(throws: HNSWStorageError.invalidDimension(expected: 3, actual: 2)) {
      try await storage.rebuildIndex()
    }

    let candidates = try await storage.searchVectorCandidates(
      queryEmbedding: [0, 1, 0],
      topK: 1,
      prefilterSize: 1
    )

    #expect(candidates?.first == banana.id)
  }

  @Test("mutation recovery surfaces failed rebuild")
  func mutationRecoverySurfacesFailedRebuild() async throws {
    let directory = try temporaryDirectory()
    let config = try HNSWConfig(
      exactSearchThreshold: 0,
      automaticCompactionDeletedRatio: 0,
      automaticCompactionMinimumDeletedCount: 1
    )
    let storage = try HNSWStorageProvider(directoryURL: directory, dimension: 3, config: config)
    let apple = VecturaDocument(text: "apple", embedding: [1, 0, 0])
    let id = UUID()
    let banana = VecturaDocument(id: id, text: "banana", embedding: [0, 1, 0])
    let updatedBanana = VecturaDocument(id: id, text: "updated banana", embedding: [0, 0, 1])

    try await storage.saveDocuments([apple, banana])
    try corruptEmbedding(for: apple.id, in: directory, embedding: [1, 0])

    var surfacedRecoveryFailure = false
    do {
      try await storage.saveDocument(updatedBanana)
    } catch HNSWStorageError.indexRecoveryFailed(let operation, let originalError, let rebuildError) {
      surfacedRecoveryFailure = operation == "saveDocument"
        && originalError.contains("invalidDimension")
        && rebuildError.contains("invalidDimension")
    }

    #expect(surfacedRecoveryFailure)
  }

  @Test("validated recovery rebuilds stale snapshot")
  func validatedRecoveryRebuildsStaleSnapshot() async throws {
    let directory = try temporaryDirectory()
    let storage = try HNSWStorageProvider(directoryURL: directory, dimension: 3)
    let apple = VecturaDocument(text: "apple", embedding: [1, 0, 0])
    let banana = VecturaDocument(text: "banana", embedding: [0, 1, 0])

    try await storage.saveDocument(apple)
    try await storage.saveIndexSnapshot()
    try await storage.saveDocument(banana)

    let reopened = try HNSWStorageProvider(
      directoryURL: directory,
      dimension: 3,
      recoveryPolicy: .validateSnapshotIfAvailable
    )

    let report = await reopened.recoveryReport
    let candidates = try await reopened.searchVectorCandidates(
      queryEmbedding: [0, 1, 0],
      topK: 1,
      prefilterSize: 2
    )

    #expect(report.loadedSnapshot == true)
    #expect(report.rebuiltFromDocuments == true)
    #expect(candidates?.first == banana.id)
  }

  @Test("validated recovery rebuilds snapshot after document update")
  func validatedRecoveryRebuildsSnapshotAfterDocumentUpdate() async throws {
    let directory = try temporaryDirectory()
    let config = try HNSWConfig(exactSearchThreshold: 0)
    let storage = try HNSWStorageProvider(directoryURL: directory, dimension: 3, config: config)
    let id = UUID()
    let old = VecturaDocument(id: id, text: "old", embedding: [1, 0, 0])
    let updated = VecturaDocument(id: id, text: "updated", embedding: [0, 1, 0])

    try await storage.saveDocument(old)
    try await storage.saveIndexSnapshot()
    try await storage.saveDocument(updated)

    let reopened = try HNSWStorageProvider(
      directoryURL: directory,
      dimension: 3,
      config: config,
      recoveryPolicy: .validateSnapshotIfAvailable
    )

    let report = await reopened.recoveryReport
    let candidates = try await reopened.searchVectorCandidates(
      queryEmbedding: [0, 1, 0],
      topK: 1,
      prefilterSize: 1
    )
    let document = try await reopened.getDocument(id: id)

    #expect(report.loadedSnapshot == true)
    #expect(report.rebuiltFromDocuments == true)
    #expect(report.reason == "Snapshot revision did not match SQLite")
    #expect(candidates?.first == id)
    #expect(document?.text == "updated")
  }

  @Test("automatic compaction removes deleted nodes")
  func automaticCompactionRemovesDeletedNodes() async throws {
    let directory = try temporaryDirectory()
    let config = try HNSWConfig(
      automaticCompactionDeletedRatio: 0,
      automaticCompactionMinimumDeletedCount: 1
    )
    let storage = try HNSWStorageProvider(directoryURL: directory, dimension: 3, config: config)
    let apple = VecturaDocument(text: "apple", embedding: [1, 0, 0])
    let banana = VecturaDocument(text: "banana", embedding: [0, 1, 0])

    try await storage.saveDocuments([apple, banana])
    try await storage.deleteDocument(withID: apple.id)

    let stats = await storage.stats
    let candidates = try await storage.searchVectorCandidates(
      queryEmbedding: [0, 1, 0],
      topK: 1,
      prefilterSize: 1
    )

    #expect(stats.deletedNodeCount == 0)
    #expect(stats.activeNodeCount == 1)
    #expect((stats.snapshotBytes ?? 0) > 0)
    #expect(candidates?.first == banana.id)
  }

  @Test("config decodes missing new fields with production defaults")
  func configDecodesMissingNewFieldsWithProductionDefaults() throws {
    let data = Data(
      """
      {
        "m": 16,
        "efConstruction": 200,
        "efSearch": 64,
        "randomSeed": 6216727343042806088,
        "metric": "cosine"
      }
      """.utf8
    )

    let config = try JSONDecoder().decode(HNSWConfig.self, from: data)

    #expect(config.level0NeighborMultiplier == 2)
    #expect(config.level0NeighborCap == 32)
    #expect(config.exactSearchThreshold == 10_000)
    #expect(config.automaticCompactionDeletedRatio == 0.30)
    #expect(config.automaticCompactionMinimumDeletedCount == 1_000)
    #expect(config.batchInsertionSeed == nil)
  }

  @Test("batch insertion seed preserves stored documents")
  func batchInsertionSeedPreservesStoredDocuments() async throws {
    let directory = try temporaryDirectory()
    let config = try HNSWConfig(batchInsertionSeed: 42)
    let storage = try HNSWStorageProvider(directoryURL: directory, dimension: 3, config: config)
    let documents = [
      VecturaDocument(text: "apple", embedding: [1, 0, 0]),
      VecturaDocument(text: "banana", embedding: [0, 1, 0]),
      VecturaDocument(text: "car", embedding: [0, 0, 1]),
    ]

    try await storage.saveDocuments(documents)
    let loaded = try await storage.loadDocuments()
    let candidates = try await storage.searchVectorCandidates(
      queryEmbedding: [1, 0, 0],
      topK: 1,
      prefilterSize: 2
    )

    #expect(Set(loaded.map(\.id)) == Set(documents.map(\.id)))
    #expect(candidates?.first == documents[0].id)
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("VecturaHNSWKitTests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func corruptEmbedding(for id: UUID, in directory: URL, embedding: [Float]) throws {
    var database: OpaquePointer?
    let databaseURL = directory.appendingPathComponent("documents.sqlite3")
    guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
      throw HNSWStorageError.sqlite(Self.sqliteMessage(from: database))
    }
    defer { sqlite3_close(database) }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
      database,
      "UPDATE documents SET embedding = ? WHERE id = ?",
      -1,
      &statement,
      nil
    ) == SQLITE_OK else {
      throw HNSWStorageError.sqlite(Self.sqliteMessage(from: database))
    }
    defer { sqlite3_finalize(statement) }

    let embeddingData = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
    _ = embeddingData.withUnsafeBytes { buffer in
      sqlite3_bind_blob(
        statement,
        1,
        buffer.baseAddress,
        Int32(buffer.count),
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      )
    }
    sqlite3_bind_text(
      statement,
      2,
      id.uuidString,
      -1,
      unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    )

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw HNSWStorageError.sqlite(Self.sqliteMessage(from: database))
    }
  }

  private static func sqliteMessage(from database: OpaquePointer?) -> String {
    guard let database, let message = sqlite3_errmsg(database) else {
      return "unknown SQLite failure"
    }
    return String(cString: message)
  }
}

/// Delegates every storage operation to a wrapped ``HNSWStorageProvider`` while
/// counting `searchText` invocations, so tests can assert that VecturaKit's text
/// search actually routes through the storage hook instead of the in-memory fallback.
private actor TextSearchSpyStorage: IndexedVecturaStorage {
  private let wrapped: HNSWStorageProvider
  private(set) var searchTextCallCount = 0

  init(wrapping wrapped: HNSWStorageProvider) {
    self.wrapped = wrapped
  }

  func createStorageDirectoryIfNeeded() async throws {
    try await wrapped.createStorageDirectoryIfNeeded()
  }

  func loadDocuments() async throws -> [VecturaDocument] {
    try await wrapped.loadDocuments()
  }

  func saveDocument(_ document: VecturaDocument) async throws {
    try await wrapped.saveDocument(document)
  }

  func saveDocuments(_ documents: [VecturaDocument]) async throws {
    try await wrapped.saveDocuments(documents)
  }

  func deleteDocument(withID id: UUID) async throws {
    try await wrapped.deleteDocument(withID: id)
  }

  func updateDocument(_ document: VecturaDocument) async throws {
    try await wrapped.updateDocument(document)
  }

  func getTotalDocumentCount() async throws -> Int {
    try await wrapped.getTotalDocumentCount()
  }

  func getDocument(id: UUID) async throws -> VecturaDocument? {
    try await wrapped.getDocument(id: id)
  }

  func documentExists(id: UUID) async throws -> Bool {
    try await wrapped.documentExists(id: id)
  }

  func loadDocuments(offset: Int, limit: Int) async throws -> [VecturaDocument] {
    try await wrapped.loadDocuments(offset: offset, limit: limit)
  }

  func loadDocuments(ids: [UUID]) async throws -> [UUID: VecturaDocument] {
    try await wrapped.loadDocuments(ids: ids)
  }

  func searchVectorCandidates(
    queryEmbedding: [Float],
    topK: Int,
    prefilterSize: Int
  ) async throws -> [UUID]? {
    try await wrapped.searchVectorCandidates(
      queryEmbedding: queryEmbedding,
      topK: topK,
      prefilterSize: prefilterSize
    )
  }

  func searchText(query: String, topK: Int) async throws -> [VecturaSearchResult]? {
    searchTextCallCount += 1
    return try await wrapped.searchText(query: query, topK: topK)
  }
}

private struct DictionaryEmbedder: VecturaEmbedder {
  let dimension: Int
  let embeddings: [String: [Float]]

  func embed(texts: [String]) async throws -> [[Float]] {
    try texts.map { text in
      guard let embedding = embeddings[text] else {
        throw HNSWStorageError.invalidConfiguration("Missing test embedding for \(text)")
      }
      return embedding
    }
  }
}
