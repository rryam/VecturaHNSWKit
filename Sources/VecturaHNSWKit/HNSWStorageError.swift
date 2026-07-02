import Foundation

/// Errors thrown by VecturaHNSWKit.
public enum HNSWStorageError: Error, Equatable, LocalizedError {
  case invalidConfiguration(String)
  case invalidDimension(expected: Int, actual: Int)
  case invalidDocumentID(String)
  case indexRecoveryFailed(operation: String, originalError: String, rebuildError: String)
  case sqlite(String)
  case storageClosed

  public var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let message):
      return message
    case .invalidDimension(let expected, let actual):
      return "Expected vector dimension \(expected), got \(actual)"
    case .invalidDocumentID(let value):
      return "Invalid document ID: \(value)"
    case .indexRecoveryFailed(let operation, let originalError, let rebuildError):
      return """
      HNSW index recovery failed after \(operation). Original error: \(originalError). \
      Rebuild error: \(rebuildError)
      """
    case .sqlite(let message):
      return "SQLite error: \(message)"
    case .storageClosed:
      return "Storage is closed"
    }
  }
}
