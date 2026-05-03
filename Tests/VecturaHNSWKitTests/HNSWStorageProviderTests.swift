import Foundation
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

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("VecturaHNSWKitTests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
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
