import Foundation
import SQLite3
import VecturaKit

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteDocumentStore {
  private var database: OpaquePointer?
  private var cachedLoadDocumentByIDStatement: OpaquePointer?
  private let dimension: Int

  init(databaseURL: URL, dimension: Int) throws {
    self.dimension = dimension

    let status = sqlite3_open_v2(
      databaseURL.path,
      &database,
      SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
      nil
    )
    guard status == SQLITE_OK else {
      throw HNSWStorageError.sqlite(Self.message(from: database))
    }

    try execute("PRAGMA journal_mode=WAL")
    try execute("PRAGMA synchronous=NORMAL")
    try createSchema()
  }

  deinit {
    sqlite3_finalize(cachedLoadDocumentByIDStatement)
    sqlite3_close(database)
  }

  func saveDocument(_ document: VecturaDocument) throws {
    try validate(document)
    try withTransaction {
      try upsert(document)
      try incrementDocumentRevision()
      try markTextIndexCurrent()
    }
  }

  func saveDocuments(_ documents: [VecturaDocument]) throws {
    guard !documents.isEmpty else {
      return
    }
    try documents.forEach(validate)
    try withTransaction {
      for document in documents {
        try upsert(document)
      }
      try incrementDocumentRevision()
      try markTextIndexCurrent()
    }
  }

  func deleteDocument(id: UUID) throws {
    try withTransaction {
      let statement = try prepare("UPDATE documents SET active = 0 WHERE id = ? AND active = 1")
      defer { sqlite3_finalize(statement) }

      sqlite3_bind_text(statement, 1, id.uuidString, -1, sqliteTransient)
      try stepDone(statement)
      if sqlite3_changes(database) > 0 {
        try deleteTextIndexEntry(id: id)
        try incrementDocumentRevision()
        try markTextIndexCurrent()
      }
    }
  }

  func loadActiveDocuments() throws -> [VecturaDocument] {
    try loadDocuments(
      sql: "SELECT id, text, embedding, created_at FROM documents WHERE active = 1 ORDER BY rowid",
      bind: { _ in }
    )
  }

  func loadDocuments(offset: Int, limit: Int) throws -> [VecturaDocument] {
    let boundedOffset = max(offset, 0)
    let boundedLimit = max(limit, 0)
    return try loadDocuments(
      sql: """
      SELECT id, text, embedding, created_at
      FROM documents
      WHERE active = 1
      ORDER BY rowid
      LIMIT ? OFFSET ?
      """,
      bind: { statement in
        sqlite3_bind_int64(statement, 1, sqlite3_int64(boundedLimit))
        sqlite3_bind_int64(statement, 2, sqlite3_int64(boundedOffset))
      }
    )
  }

  func loadDocuments(ids: [UUID]) throws -> [UUID: VecturaDocument] {
    guard !ids.isEmpty else {
      return [:]
    }

    var results: [UUID: VecturaDocument] = [:]

    if ids.count <= 512 {
      for id in ids {
        if let document = try loadDocument(id: id) {
          results[id] = document
        }
      }
      return results
    }

    for startIndex in stride(from: 0, to: ids.count, by: 500) {
      let endIndex = min(startIndex + 500, ids.count)
      let chunk = Array(ids[startIndex..<endIndex])
      let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
      let documents = try loadDocuments(
        sql: """
        SELECT id, text, embedding, created_at
        FROM documents
        WHERE active = 1 AND id IN (\(placeholders))
        """,
        bind: { statement in
          for (index, id) in chunk.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), id.uuidString, -1, sqliteTransient)
          }
        }
      )

      for document in documents {
        results[document.id] = document
      }
    }

    return results
  }

  func loadDocument(id: UUID) throws -> VecturaDocument? {
    let statement = try loadDocumentByIDStatement()
    defer {
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
    }

    sqlite3_bind_text(statement, 1, id.uuidString, -1, sqliteTransient)
    let status = sqlite3_step(statement)
    switch status {
    case SQLITE_ROW:
      return try decodeDocument(from: statement)
    case SQLITE_DONE:
      return nil
    default:
      throw HNSWStorageError.sqlite(Self.message(from: database))
    }
  }

  func countActiveDocuments() throws -> Int {
    let statement = try prepare("SELECT COUNT(*) FROM documents WHERE active = 1")
    defer { sqlite3_finalize(statement) }

    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw HNSWStorageError.sqlite(Self.message(from: database))
    }
    return Int(sqlite3_column_int64(statement, 0))
  }

  func currentDocumentRevision() throws -> Int64 {
    let statement = try prepare("SELECT value FROM metadata WHERE key = 'documentRevision' LIMIT 1")
    defer { sqlite3_finalize(statement) }

    guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
      return 0
    }

    return Int64(String(cString: value)) ?? 0
  }

  func documentExists(id: UUID) throws -> Bool {
    let statement = try prepare("SELECT 1 FROM documents WHERE active = 1 AND id = ? LIMIT 1")
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, id.uuidString, -1, sqliteTransient)
    return sqlite3_step(statement) == SQLITE_ROW
  }

  func searchText(query: String, topK: Int) throws -> [VecturaSearchResult] {
    guard topK > 0, let ftsQuery = Self.ftsQuery(for: query) else {
      return []
    }

    let statement = try prepare(
      """
      SELECT id, text, created_at, -bm25(document_text_index) AS score
      FROM document_text_index
      WHERE document_text_index MATCH ?
      ORDER BY bm25(document_text_index), rowid
      LIMIT ?
      """
    )
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, ftsQuery, -1, sqliteTransient)
    sqlite3_bind_int64(statement, 2, sqlite3_int64(topK))

    var results: [VecturaSearchResult] = []
    while true {
      let status = sqlite3_step(statement)
      switch status {
      case SQLITE_ROW:
        guard let idText = sqlite3_column_text(statement, 0),
              let textValue = sqlite3_column_text(statement, 1),
              let id = UUID(uuidString: String(cString: idText)) else {
          throw HNSWStorageError.sqlite("Failed to decode text search row")
        }

        results.append(
          VecturaSearchResult(
            id: id,
            text: String(cString: textValue),
            score: Float(sqlite3_column_double(statement, 3)),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
          )
        )
      case SQLITE_DONE:
        return results
      default:
        throw HNSWStorageError.sqlite(Self.message(from: database))
      }
    }
  }

  private func createSchema() throws {
    try execute(
      """
      CREATE TABLE IF NOT EXISTS documents (
        id TEXT PRIMARY KEY NOT NULL,
        text TEXT NOT NULL,
        embedding BLOB NOT NULL,
        created_at REAL NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      )
      """
    )
    try execute("CREATE INDEX IF NOT EXISTS idx_documents_active ON documents(active)")
    try execute(
      """
      CREATE VIRTUAL TABLE IF NOT EXISTS document_text_index
      USING fts5(
        id UNINDEXED,
        text,
        created_at UNINDEXED,
        tokenize = 'unicode61 remove_diacritics 1'
      )
      """
    )
    try execute(
      """
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )
      """
    )
    try setMetadata(key: "dimension", value: String(dimension))
    try setMetadataIfMissing(key: "documentRevision", value: "0")
    try setMetadataIfMissing(key: "textIndexRevision", value: "-1")
    if try metadataValue(key: "textIndexRevision") != metadataValue(key: "documentRevision") {
      try rebuildTextIndex()
      try markTextIndexCurrent()
    }
  }

  private func setMetadata(key: String, value: String) throws {
    let statement = try prepare(
      """
      INSERT INTO metadata(key, value)
      VALUES(?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      """
    )
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)
    sqlite3_bind_text(statement, 2, value, -1, sqliteTransient)
    try stepDone(statement)
  }

  private func setMetadataIfMissing(key: String, value: String) throws {
    let statement = try prepare(
      """
      INSERT OR IGNORE INTO metadata(key, value)
      VALUES(?, ?)
      """
    )
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)
    sqlite3_bind_text(statement, 2, value, -1, sqliteTransient)
    try stepDone(statement)
  }

  private func incrementDocumentRevision() throws {
    let currentRevision = try currentDocumentRevision()
    try setMetadata(key: "documentRevision", value: String(currentRevision + 1))
  }

  private func upsert(_ document: VecturaDocument) throws {
    let statement = try prepare(
      """
      INSERT INTO documents(id, text, embedding, created_at, active)
      VALUES(?, ?, ?, ?, 1)
      ON CONFLICT(id) DO UPDATE SET
        text = excluded.text,
        embedding = excluded.embedding,
        created_at = excluded.created_at,
        active = 1
      """
    )
    defer { sqlite3_finalize(statement) }

    let embeddingData = Self.encodeEmbedding(document.embedding)
    sqlite3_bind_text(statement, 1, document.id.uuidString, -1, sqliteTransient)
    sqlite3_bind_text(statement, 2, document.text, -1, sqliteTransient)
    _ = embeddingData.withUnsafeBytes { buffer in
      sqlite3_bind_blob(statement, 3, buffer.baseAddress, Int32(buffer.count), sqliteTransient)
    }
    sqlite3_bind_double(statement, 4, document.createdAt.timeIntervalSince1970)
    try stepDone(statement)
    try upsertTextIndexEntry(for: document)
  }

  private func metadataValue(key: String) throws -> String? {
    let statement = try prepare("SELECT value FROM metadata WHERE key = ? LIMIT 1")
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)
    guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
      return nil
    }
    return String(cString: value)
  }

  private func markTextIndexCurrent() throws {
    let revision = try currentDocumentRevision()
    try setMetadata(key: "textIndexRevision", value: String(revision))
  }

  private func rebuildTextIndex() throws {
    try withTransaction {
      try execute("DELETE FROM document_text_index")
      let documents = try loadActiveDocuments()
      for document in documents {
        try insertTextIndexEntry(for: document)
      }
    }
  }

  private func upsertTextIndexEntry(for document: VecturaDocument) throws {
    try deleteTextIndexEntry(id: document.id)
    try insertTextIndexEntry(for: document)
  }

  private func insertTextIndexEntry(for document: VecturaDocument) throws {
    let rowID = try documentRowID(id: document.id)
    let statement = try prepare(
      """
      INSERT INTO document_text_index(rowid, id, text, created_at)
      VALUES(?, ?, ?, ?)
      """
    )
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_int64(statement, 1, sqlite3_int64(rowID))
    sqlite3_bind_text(statement, 2, document.id.uuidString, -1, sqliteTransient)
    sqlite3_bind_text(statement, 3, document.text, -1, sqliteTransient)
    sqlite3_bind_double(statement, 4, document.createdAt.timeIntervalSince1970)
    try stepDone(statement)
  }

  private func deleteTextIndexEntry(id: UUID) throws {
    let statement = try prepare("DELETE FROM document_text_index WHERE id = ?")
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, id.uuidString, -1, sqliteTransient)
    try stepDone(statement)
  }

  private func documentRowID(id: UUID) throws -> Int64 {
    let statement = try prepare("SELECT rowid FROM documents WHERE id = ? LIMIT 1")
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, id.uuidString, -1, sqliteTransient)
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw HNSWStorageError.sqlite("Failed to find document rowid")
    }
    return sqlite3_column_int64(statement, 0)
  }

  private func validate(_ document: VecturaDocument) throws {
    guard document.embedding.count == dimension else {
      throw HNSWStorageError.invalidDimension(expected: dimension, actual: document.embedding.count)
    }
  }

  private func loadDocuments(
    sql: String,
    bind: (OpaquePointer?) throws -> Void
  ) throws -> [VecturaDocument] {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    try bind(statement)
    var documents: [VecturaDocument] = []

    while true {
      let status = sqlite3_step(statement)
      switch status {
      case SQLITE_ROW:
        documents.append(try decodeDocument(from: statement))
      case SQLITE_DONE:
        return documents
      default:
        throw HNSWStorageError.sqlite(Self.message(from: database))
      }
    }
  }

  private func decodeDocument(from statement: OpaquePointer?) throws -> VecturaDocument {
    guard let idText = sqlite3_column_text(statement, 0),
          let textValue = sqlite3_column_text(statement, 1),
          let id = UUID(uuidString: String(cString: idText)) else {
      throw HNSWStorageError.sqlite("Failed to decode document row")
    }

    let text = String(cString: textValue)
    let embeddingBytes = sqlite3_column_blob(statement, 2)
    let embeddingByteCount = Int(sqlite3_column_bytes(statement, 2))
    let embeddingData = embeddingBytes.map { Data(bytes: $0, count: embeddingByteCount) } ?? Data()
    let embedding = try Self.decodeEmbedding(embeddingData, dimension: dimension)
    let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))

    return VecturaDocument(id: id, text: text, embedding: embedding, createdAt: createdAt)
  }

  private func withTransaction<T>(_ work: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE TRANSACTION")
    do {
      let value = try work()
      try execute("COMMIT")
      return value
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw HNSWStorageError.sqlite(Self.message(from: database))
    }
    return statement
  }

  private func loadDocumentByIDStatement() throws -> OpaquePointer? {
    if let cachedLoadDocumentByIDStatement {
      return cachedLoadDocumentByIDStatement
    }

    cachedLoadDocumentByIDStatement = try prepare(
      """
      SELECT id, text, embedding, created_at
      FROM documents
      WHERE active = 1 AND id = ?
      LIMIT 1
      """
    )
    return cachedLoadDocumentByIDStatement
  }

  private func execute(_ sql: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
      let message = errorMessage.map { String(cString: $0) } ?? Self.message(from: database)
      sqlite3_free(errorMessage)
      throw HNSWStorageError.sqlite(message)
    }
  }

  private func stepDone(_ statement: OpaquePointer?) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw HNSWStorageError.sqlite(Self.message(from: database))
    }
  }

  private static func encodeEmbedding(_ embedding: [Float]) -> Data {
    embedding.withUnsafeBufferPointer { buffer in
      Data(buffer: buffer)
    }
  }

  private static func decodeEmbedding(_ data: Data, dimension: Int) throws -> [Float] {
    guard data.count == dimension * MemoryLayout<Float>.stride else {
      throw HNSWStorageError.invalidDimension(
        expected: dimension,
        actual: data.count / MemoryLayout<Float>.stride
      )
    }

    var embedding = [Float](repeating: 0, count: dimension)
    _ = embedding.withUnsafeMutableBytes { destination in
      data.copyBytes(to: destination)
    }
    return embedding
  }

  private static func message(from database: OpaquePointer?) -> String {
    guard let database, let message = sqlite3_errmsg(database) else {
      return "unknown SQLite failure"
    }
    return String(cString: message)
  }

  private static func ftsQuery(for query: String) -> String? {
    let terms = query
      .lowercased()
      .folding(options: .diacriticInsensitive, locale: .current)
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }

    guard !terms.isEmpty else {
      return nil
    }

    return terms
      .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
      .joined(separator: " OR ")
  }
}
