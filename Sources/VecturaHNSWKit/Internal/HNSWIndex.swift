import Foundation
import VecturaKit

struct HNSWScoredNode {
  let id: Int
  let score: Float
}

struct HNSWIndexSnapshot: Codable {
  let formatVersion: Int
  let dimension: Int
  let config: HNSWConfig
  let rng: SeededGenerator
  let nodes: [HNSWNode]
  let activeDocumentNodes: [UUID: Int]
  let entryPoint: Int?
  let maxLayer: Int
}

struct HNSWNode: Codable {
  let id: Int
  let documentID: UUID
  let vector: [Float]
  let level: Int
  var neighborsByLayer: [[Int]]
  var isDeleted: Bool
}

final class HNSWIndex {
  private let dimension: Int
  private let config: HNSWConfig
  private var rng: SeededGenerator
  private var nodes: [HNSWNode] = []
  private var activeDocumentNodes: [UUID: Int] = [:]
  private var entryPoint: Int?
  private var maxLayer = -1

  init(dimension: Int, config: HNSWConfig) throws {
    guard dimension > 0 else {
      throw HNSWStorageError.invalidConfiguration("dimension must be greater than 0")
    }

    self.dimension = dimension
    self.config = config
    self.rng = SeededGenerator(seed: config.randomSeed)
  }

  var stats: HNSWIndexStats {
    let deletedCount = nodes.reduce(0) { $0 + ($1.isDeleted ? 1 : 0) }
    return HNSWIndexStats(
      dimension: dimension,
      documentCount: activeDocumentNodes.count,
      activeNodeCount: activeDocumentNodes.count,
      deletedNodeCount: deletedCount,
      maxLayer: maxLayer
    )
  }

  var activeDocumentIDs: Set<UUID> {
    Set(activeDocumentNodes.keys)
  }

  func rebuild(documents: [VecturaDocument]) throws {
    nodes.removeAll(keepingCapacity: true)
    activeDocumentNodes.removeAll(keepingCapacity: true)
    entryPoint = nil
    maxLayer = -1
    rng = SeededGenerator(seed: config.randomSeed)

    for document in documents {
      try add(documentID: document.id, vector: document.embedding)
    }
  }

  func snapshot() -> HNSWIndexSnapshot {
    HNSWIndexSnapshot(
      formatVersion: 1,
      dimension: dimension,
      config: config,
      rng: rng,
      nodes: nodes,
      activeDocumentNodes: activeDocumentNodes,
      entryPoint: entryPoint,
      maxLayer: maxLayer
    )
  }

  func restore(from snapshot: HNSWIndexSnapshot) throws {
    guard snapshot.formatVersion == 1 else {
      throw HNSWStorageError.invalidConfiguration("Unsupported HNSW snapshot version")
    }
    guard snapshot.dimension == dimension else {
      throw HNSWStorageError.invalidDimension(expected: dimension, actual: snapshot.dimension)
    }
    guard snapshot.config.m == config.m,
          snapshot.config.metric == config.metric else {
      throw HNSWStorageError.invalidConfiguration("HNSW snapshot config does not match storage config")
    }

    rng = snapshot.rng
    nodes = snapshot.nodes
    activeDocumentNodes = snapshot.activeDocumentNodes
    entryPoint = snapshot.entryPoint
    maxLayer = snapshot.maxLayer
  }

  @discardableResult
  func add(documentID: UUID, vector: [Float]) throws -> Int {
    let normalizedVector = try VectorScoring.normalized(vector, dimension: dimension)
    if let existingNodeID = activeDocumentNodes[documentID] {
      nodes[existingNodeID].isDeleted = true
    }

    let nodeLevel = randomLevel()
    let nodeID = nodes.count
    let node = HNSWNode(
      id: nodeID,
      documentID: documentID,
      vector: normalizedVector,
      level: nodeLevel,
      neighborsByLayer: Array(repeating: [], count: nodeLevel + 1),
      isDeleted: false
    )
    nodes.append(node)
    activeDocumentNodes[documentID] = nodeID

    guard let currentEntryPoint = entryPoint else {
      entryPoint = nodeID
      maxLayer = nodeLevel
      return nodeID
    }

    var nearestEntry = currentEntryPoint
    if maxLayer > nodeLevel {
      for layer in stride(from: maxLayer, through: nodeLevel + 1, by: -1) {
        nearestEntry = greedySearch(query: normalizedVector, entryPoint: nearestEntry, layer: layer)
      }
    }

    let topLayer = min(nodeLevel, maxLayer)
    if topLayer >= 0 {
      for layer in stride(from: topLayer, through: 0, by: -1) {
        let candidates = searchLayer(
          query: normalizedVector,
          entryPoints: [nearestEntry],
          ef: config.efConstruction,
          layer: layer
        )
        let selected = selectNeighbors(for: normalizedVector, candidates: candidates, layer: layer)
        connect(nodeID: nodeID, neighbors: selected, layer: layer)
        if let best = candidates.first {
          nearestEntry = best.id
        }
      }
    }

    if nodeLevel > maxLayer {
      entryPoint = nodeID
      maxLayer = nodeLevel
    }

    return nodeID
  }

  func markDeleted(documentID: UUID) {
    guard let nodeID = activeDocumentNodes.removeValue(forKey: documentID) else {
      return
    }
    nodes[nodeID].isDeleted = true
  }

  func search(query: [Float], limit: Int, efSearch: Int? = nil) throws -> [UUID] {
    guard limit > 0, let entryPoint else {
      return []
    }

    let normalizedQuery = try VectorScoring.normalized(query, dimension: dimension)
    var nearestEntry = entryPoint

    if maxLayer > 0 {
      for layer in stride(from: maxLayer, through: 1, by: -1) {
        nearestEntry = greedySearch(query: normalizedQuery, entryPoint: nearestEntry, layer: layer)
      }
    }

    let searchBreadth = max(limit, efSearch ?? config.efSearch)
    let candidates = searchLayer(
      query: normalizedQuery,
      entryPoints: [nearestEntry],
      ef: searchBreadth,
      layer: 0
    )

    var results: [UUID] = []
    var seen = Set<UUID>()
    results.reserveCapacity(limit)

    for candidate in candidates {
      let node = nodes[candidate.id]
      guard !node.isDeleted else {
        continue
      }
      guard activeDocumentNodes[node.documentID] == node.id else {
        continue
      }
      guard seen.insert(node.documentID).inserted else {
        continue
      }

      results.append(node.documentID)
      if results.count == limit {
        break
      }
    }

    return results
  }

  private func randomLevel() -> Int {
    let multiplier = 1.0 / Foundation.log(Double(max(config.m, 2)))
    let value = max(rng.nextUnitDouble(), Double.leastNonzeroMagnitude)
    return Int(-Foundation.log(value) * multiplier)
  }

  private func greedySearch(query: [Float], entryPoint: Int, layer: Int) -> Int {
    var current = entryPoint
    var currentScore = score(query: query, nodeID: current)
    var changed = true

    while changed {
      changed = false
      for neighborID in neighbors(of: current, layer: layer) {
        let neighborScore = score(query: query, nodeID: neighborID)
        if neighborScore > currentScore {
          current = neighborID
          currentScore = neighborScore
          changed = true
        }
      }
    }

    return current
  }

  private func searchLayer(
    query: [Float],
    entryPoints: [Int],
    ef: Int,
    layer: Int
  ) -> [HNSWScoredNode] {
    var visited = Set<Int>()
    var candidates: [HNSWScoredNode] = []
    var nearest: [HNSWScoredNode] = []

    for entryPoint in entryPoints {
      guard visited.insert(entryPoint).inserted else {
        continue
      }
      let scored = HNSWScoredNode(id: entryPoint, score: score(query: query, nodeID: entryPoint))
      candidates.append(scored)
      nearest.append(scored)
    }

    candidates.sort { $0.score > $1.score }
    nearest.sort { $0.score > $1.score }

    while !candidates.isEmpty {
      let current = candidates.removeFirst()
      if nearest.count >= ef, let worst = nearest.last, current.score < worst.score {
        break
      }

      for neighborID in neighbors(of: current.id, layer: layer) where visited.insert(neighborID).inserted {
        let scored = HNSWScoredNode(id: neighborID, score: score(query: query, nodeID: neighborID))
        if nearest.count < ef || scored.score > (nearest.last?.score ?? -.infinity) {
          candidates.append(scored)
          nearest.append(scored)
          candidates.sort { $0.score > $1.score }
          nearest.sort { $0.score > $1.score }

          if nearest.count > ef {
            nearest.removeLast()
          }
        }
      }
    }

    return nearest.sorted { $0.score > $1.score }
  }

  private func selectNeighbors(
    for vector: [Float],
    candidates: [HNSWScoredNode],
    layer: Int
  ) -> [Int] {
    var seen = Set<Int>()
    return candidates
      .filter { nodes[$0.id].level >= layer }
      .filter { seen.insert($0.id).inserted }
      .sorted { score(vector: vector, nodeID: $0.id) > score(vector: vector, nodeID: $1.id) }
      .prefix(config.m)
      .map(\.id)
  }

  private func connect(nodeID: Int, neighbors: [Int], layer: Int) {
    guard nodes[nodeID].neighborsByLayer.indices.contains(layer) else {
      return
    }

    nodes[nodeID].neighborsByLayer[layer] = neighbors
    for neighborID in neighbors where nodes[neighborID].neighborsByLayer.indices.contains(layer) {
      if !nodes[neighborID].neighborsByLayer[layer].contains(nodeID) {
        nodes[neighborID].neighborsByLayer[layer].append(nodeID)
      }
      pruneNeighbors(of: neighborID, layer: layer)
    }
  }

  private func pruneNeighbors(of nodeID: Int, layer: Int) {
    let baseVector = nodes[nodeID].vector
    var unique = Array(Set(nodes[nodeID].neighborsByLayer[layer]))
    unique.sort {
      score(vector: baseVector, nodeID: $0) > score(vector: baseVector, nodeID: $1)
    }
    nodes[nodeID].neighborsByLayer[layer] = Array(unique.prefix(config.m))
  }

  private func neighbors(of nodeID: Int, layer: Int) -> [Int] {
    guard nodes.indices.contains(nodeID),
          nodes[nodeID].neighborsByLayer.indices.contains(layer) else {
      return []
    }
    return nodes[nodeID].neighborsByLayer[layer]
  }

  private func score(query: [Float], nodeID: Int) -> Float {
    VectorScoring.cosine(query, nodes[nodeID].vector)
  }

  private func score(vector: [Float], nodeID: Int) -> Float {
    VectorScoring.cosine(vector, nodes[nodeID].vector)
  }
}
