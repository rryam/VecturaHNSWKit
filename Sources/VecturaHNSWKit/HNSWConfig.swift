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

  /// Document-count threshold where exact candidate selection is preferred over graph traversal.
  ///
  /// Set to `0` to always use HNSW candidate search. The default keeps small corpora on
  /// exact candidate selection so high-recall searches do not pay graph overhead too early.
  public var exactSearchThreshold: Int

  /// Deleted-node ratio that triggers automatic compaction.
  ///
  /// Compaction also requires at least `automaticCompactionMinimumDeletedCount` deleted nodes.
  public var automaticCompactionDeletedRatio: Double

  /// Minimum deleted-node count required before automatic compaction runs.
  public var automaticCompactionMinimumDeletedCount: Int

  public static let `default` = try! HNSWConfig()

  enum CodingKeys: String, CodingKey {
    case m
    case efConstruction
    case efSearch
    case randomSeed
    case metric
    case exactSearchThreshold
    case automaticCompactionDeletedRatio
    case automaticCompactionMinimumDeletedCount
  }

  public init(
    m: Int = 16,
    efConstruction: Int = 200,
    efSearch: Int = 64,
    randomSeed: UInt64 = 0x5645_4354_5552_4148,
    metric: HNSWMetric = .cosine,
    exactSearchThreshold: Int = 10_000,
    automaticCompactionDeletedRatio: Double = 0.30,
    automaticCompactionMinimumDeletedCount: Int = 1_000
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
    guard exactSearchThreshold >= 0 else {
      throw HNSWStorageError.invalidConfiguration("exactSearchThreshold must be greater than or equal to 0")
    }
    guard automaticCompactionDeletedRatio >= 0 && automaticCompactionDeletedRatio <= 1 else {
      throw HNSWStorageError.invalidConfiguration(
        "automaticCompactionDeletedRatio must be between 0 and 1"
      )
    }
    guard automaticCompactionMinimumDeletedCount >= 0 else {
      throw HNSWStorageError.invalidConfiguration(
        "automaticCompactionMinimumDeletedCount must be greater than or equal to 0"
      )
    }

    self.m = m
    self.efConstruction = efConstruction
    self.efSearch = efSearch
    self.randomSeed = randomSeed
    self.metric = metric
    self.exactSearchThreshold = exactSearchThreshold
    self.automaticCompactionDeletedRatio = automaticCompactionDeletedRatio
    self.automaticCompactionMinimumDeletedCount = automaticCompactionMinimumDeletedCount
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      m: try container.decode(Int.self, forKey: .m),
      efConstruction: try container.decode(Int.self, forKey: .efConstruction),
      efSearch: try container.decode(Int.self, forKey: .efSearch),
      randomSeed: try container.decode(UInt64.self, forKey: .randomSeed),
      metric: try container.decode(HNSWMetric.self, forKey: .metric),
      exactSearchThreshold: try container.decodeIfPresent(Int.self, forKey: .exactSearchThreshold) ?? 10_000,
      automaticCompactionDeletedRatio: try container.decodeIfPresent(
        Double.self,
        forKey: .automaticCompactionDeletedRatio
      ) ?? 0.30,
      automaticCompactionMinimumDeletedCount: try container.decodeIfPresent(
        Int.self,
        forKey: .automaticCompactionMinimumDeletedCount
      ) ?? 1_000
    )
  }
}
