/// Configuration for the HNSW graph.
public struct HNSWConfig: Codable, Equatable, Sendable {
  /// Maximum number of graph neighbors retained per node on upper layers.
  ///
  /// The ground layer keeps a wider capped neighbor budget to improve recall:
  /// `min(m * 2, 32)`, but never less than `m`.
  public var m: Int

  /// Candidate breadth used while inserting vectors.
  public var efConstruction: Int

  /// Candidate breadth used while searching.
  public var efSearch: Int

  /// Deterministic random seed for level assignment.
  public var randomSeed: UInt64

  /// Similarity metric used by the graph.
  public var metric: HNSWMetric

  public static let `default` = try! HNSWConfig()

  public init(
    m: Int = 16,
    efConstruction: Int = 200,
    efSearch: Int = 64,
    randomSeed: UInt64 = 0x5645_4354_5552_4148,
    metric: HNSWMetric = .cosine
  ) throws {
    guard m > 0 else {
      throw HNSWStorageError.invalidConfiguration("m must be greater than 0")
    }
    guard efConstruction >= m else {
      throw HNSWStorageError.invalidConfiguration("efConstruction must be greater than or equal to m")
    }
    guard efSearch > 0 else {
      throw HNSWStorageError.invalidConfiguration("efSearch must be greater than 0")
    }

    self.m = m
    self.efConstruction = efConstruction
    self.efSearch = efSearch
    self.randomSeed = randomSeed
    self.metric = metric
  }
}
