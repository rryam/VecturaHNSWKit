import Foundation
import VecturaHNSWKit
import VecturaKit

@main
struct VecturaHNSWBenchmark {
  static func main() async throws {
    let options = BenchmarkOptions.fromEnvironment()
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("VecturaHNSWBenchmark")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let texts = (0..<options.documentCount).map { "doc-\($0)" }
    let ids = (0..<options.documentCount).map(Self.uuid)
    let queryVectors = (0..<options.queryCount).map { index in
      DeterministicVectors.vector(
        key: "doc-\((index * 7919) % options.documentCount)",
        dimension: options.dimension
      )
    }

    let embedder = BenchmarkEmbedder(dimension: options.dimension)
    let searchOptions = VecturaConfig.SearchOptions(
      defaultNumResults: options.topK,
      minThreshold: nil,
      hybridWeight: 1
    )

    let exactConfig = try VecturaConfig(
      name: "plain-vectura",
      directoryURL: root.appendingPathComponent("plain"),
      dimension: options.dimension,
      searchOptions: searchOptions,
      memoryStrategy: .fullMemory
    )
    let hnswConfig = try VecturaConfig(
      name: "hnsw-vectura",
      directoryURL: root.appendingPathComponent("hnsw-vectura"),
      dimension: options.dimension,
      searchOptions: searchOptions,
      memoryStrategy: .indexed(candidateMultiplier: options.candidateMultiplier)
    )
    let hnswStorage = try HNSWStorageProvider(
      directoryURL: root.appendingPathComponent("hnsw-store"),
      dimension: options.dimension,
      config: try HNSWConfig(
        m: options.m,
        efConstruction: options.efConstruction,
        efSearch: options.efSearch
      )
    )

    let exact = try await VecturaKit(config: exactConfig, embedder: embedder)
    let hnsw = try await VecturaKit(config: hnswConfig, embedder: embedder, storageProvider: hnswStorage)

    let exactInsert = try await timed {
      _ = try await exact.addDocuments(texts: texts, ids: ids)
    }
    let hnswInsert = try await timed {
      _ = try await hnsw.addDocuments(texts: texts, ids: ids)
    }
    let snapshotTime = try await timed {
      try await hnswStorage.saveIndexSnapshot()
    }

    let exactRun = try await measureSearch(engine: exact, queryVectors: queryVectors, topK: options.topK)
    let hnswRun = try await measureSearch(engine: hnsw, queryVectors: queryVectors, topK: options.topK)
    let recall = averageRecall(exact: exactRun.ids, candidate: hnswRun.ids)

    let coldOpen = try timedSync {
      _ = try HNSWStorageProvider(
        directoryURL: root.appendingPathComponent("hnsw-store"),
        dimension: options.dimension,
        config: try HNSWConfig(
          m: options.m,
          efConstruction: options.efConstruction,
          efSearch: options.efSearch
        )
      )
    }

    let stats = await hnswStorage.stats

    print(
      """
      # VecturaHNSWKit Benchmark

      documents: \(options.documentCount)
      dimension: \(options.dimension)
      queries: \(options.queryCount)
      topK: \(options.topK)
      candidateMultiplier: \(options.candidateMultiplier)

      | Engine | avg ms | p50 ms | p95 ms | p99 ms |
      | --- | ---: | ---: | ---: | ---: |
      | Plain VecturaKit exact scan | \(exactRun.timings.average.ms) | \(exactRun.timings.p50.ms) | \(exactRun.timings.p95.ms) | \(exactRun.timings.p99.ms) |
      | VecturaHNSWKit | \(hnswRun.timings.average.ms) | \(hnswRun.timings.p50.ms) | \(hnswRun.timings.p95.ms) | \(hnswRun.timings.p99.ms) |

      recall@\(options.topK): \(String(format: "%.4f", recall))
      plain insert: \(exactInsert.ms) ms
      hnsw insert: \(hnswInsert.ms) ms
      snapshot write: \(snapshotTime.ms) ms
      cold open with snapshot: \(coldOpen.ms) ms
      hnsw active nodes: \(stats.activeNodeCount)
      hnsw deleted nodes: \(stats.deletedNodeCount)
      hnsw max layer: \(stats.maxLayer)
      hnsw snapshot bytes: \(stats.snapshotBytes ?? 0)
      """
    )
  }

  @MainActor
  private static func measureSearch(
    engine: VecturaKit,
    queryVectors: [[Float]],
    topK: Int
  ) async throws -> (timings: TimingSummary, ids: [[UUID]]) {
    var timings: [TimeInterval] = []
    var ids: [[UUID]] = []
    timings.reserveCapacity(queryVectors.count)
    ids.reserveCapacity(queryVectors.count)

    for queryVector in queryVectors {
      let start = Date()
      let results = try await engine.search(query: .vector(queryVector), numResults: topK, threshold: nil)
      timings.append(Date().timeIntervalSince(start))
      ids.append(results.map(\.id))
    }

    return (TimingSummary(values: timings), ids)
  }

  private static func averageRecall(exact: [[UUID]], candidate: [[UUID]]) -> Double {
    guard !exact.isEmpty else {
      return 1
    }

    let total = zip(exact, candidate).reduce(0.0) { partial, pair in
      let expected = Set(pair.0)
      guard !expected.isEmpty else {
        return partial + 1
      }
      let actual = Set(pair.1)
      return partial + Double(expected.intersection(actual).count) / Double(expected.count)
    }

    return total / Double(exact.count)
  }

  private static func uuid(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
  }

  @MainActor
  private static func timed(_ work: () async throws -> Void) async throws -> TimeInterval {
    let start = Date()
    try await work()
    return Date().timeIntervalSince(start)
  }

  @MainActor
  private static func timedSync(_ work: () throws -> Void) throws -> TimeInterval {
    let start = Date()
    try work()
    return Date().timeIntervalSince(start)
  }
}

struct BenchmarkOptions {
  let documentCount: Int
  let dimension: Int
  let queryCount: Int
  let topK: Int
  let candidateMultiplier: Int
  let m: Int
  let efConstruction: Int
  let efSearch: Int

  static func fromEnvironment() -> BenchmarkOptions {
    let environment = ProcessInfo.processInfo.environment
    return BenchmarkOptions(
      documentCount: environment.integer("VECTURA_HNSW_BENCH_DOCS", default: 2_000),
      dimension: environment.integer("VECTURA_HNSW_BENCH_DIM", default: 128),
      queryCount: environment.integer("VECTURA_HNSW_BENCH_QUERIES", default: 25),
      topK: environment.integer("VECTURA_HNSW_BENCH_TOPK", default: 10),
      candidateMultiplier: environment.integer("VECTURA_HNSW_BENCH_CANDIDATE_MULTIPLIER", default: 8),
      m: environment.integer("VECTURA_HNSW_BENCH_M", default: 16),
      efConstruction: environment.integer("VECTURA_HNSW_BENCH_EF_CONSTRUCTION", default: 200),
      efSearch: environment.integer("VECTURA_HNSW_BENCH_EF_SEARCH", default: 128)
    )
  }
}

struct BenchmarkEmbedder: VecturaEmbedder {
  let dimension: Int

  func embed(texts: [String]) async throws -> [[Float]] {
    texts.map { DeterministicVectors.vector(key: $0, dimension: dimension) }
  }
}

enum DeterministicVectors {
  static func vector(key: String, dimension: Int) -> [Float] {
    var generator = BenchmarkGenerator(seed: UInt64(abs(key.hashValue)) &+ UInt64(dimension))
    var vector = [Float]()
    vector.reserveCapacity(dimension)
    for _ in 0..<dimension {
      vector.append(Float(generator.nextUnitDouble() * 2 - 1))
    }
    return normalize(vector)
  }

  private static func normalize(_ vector: [Float]) -> [Float] {
    let sum = vector.reduce(Float(0)) { $0 + $1 * $1 }
    guard sum > 0 else {
      return vector
    }
    let norm = sqrt(sum)
    return vector.map { $0 / norm }
  }
}

struct BenchmarkGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed == 0 ? 0x9e37_79b9_7f4a_7c15 : seed
  }

  mutating func next() -> UInt64 {
    state = state &* 2862933555777941757 &+ 3037000493
    return state
  }

  mutating func nextUnitDouble() -> Double {
    Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
  }
}

struct TimingSummary {
  let values: [TimeInterval]

  var average: TimeInterval {
    values.reduce(0, +) / Double(values.count)
  }

  var p50: TimeInterval {
    percentile(0.50)
  }

  var p95: TimeInterval {
    percentile(0.95)
  }

  var p99: TimeInterval {
    percentile(0.99)
  }

  private func percentile(_ value: Double) -> TimeInterval {
    let sorted = values.sorted()
    guard !sorted.isEmpty else {
      return 0
    }
    let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * value).rounded()))
    return sorted[index]
  }
}

extension TimeInterval {
  var ms: String {
    String(format: "%.3f", self * 1_000)
  }
}

extension Dictionary where Key == String, Value == String {
  func integer(_ key: String, default defaultValue: Int) -> Int {
    self[key].flatMap(Int.init) ?? defaultValue
  }
}
