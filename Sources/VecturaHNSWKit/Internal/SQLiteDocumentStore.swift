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
    }
  }

  func saveDocuments(_ documents: [VecturaDocument]) throws {
    try documents.forEach(validate)
    try withTransaction {
      for document in documents {
        try upsert(document)
      }
    }
  }

  func deleteDocument(id: UUID) throws {
    let statement = try prepare("UPDATE documents SET active = 0 WHERE id = ?")
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, id.uuidString, -1, sqliteTransient)
    try stepDone(statement)
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
    var results: [UUID: VecturaDocument] = [:]
    for id in ids {
      if let document = try loadDocument(id: id) {
        results[id] = document
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

  func documentExists(id: UUID) throws -> Bool {
    let statement = try prepare("SELECT 1 FROM documents WHERE active = 1 AND id = ? LIMIT 1")
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, id.uuidString, -1, sqliteTransient)
    return sqlite3_step(statement) == SQLITE_ROW
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
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )
      """
    )
    try setMetadata(key: "dimension", value: String(dimension))
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
}
