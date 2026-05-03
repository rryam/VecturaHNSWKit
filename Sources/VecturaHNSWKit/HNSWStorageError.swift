import Foundation

/// Errors thrown by VecturaHNSWKit.
public enum HNSWStorageError: Error, Equatable, LocalizedError {
  case invalidConfiguration(String)
  case invalidDimension(expected: Int, actual: Int)
  case invalidDocumentID(String)
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
    case .sqlite(let message):
      return "SQLite error: \(message)"
    case .storageClosed:
      return "Storage is closed"
    }
  }
}
