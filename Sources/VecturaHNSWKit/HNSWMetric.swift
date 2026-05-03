/// Distance metric used by the HNSW graph.
public enum HNSWMetric: String, Codable, Sendable {
  /// Cosine similarity over normalized vectors.
  case cosine
}
