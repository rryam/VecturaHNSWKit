import Accelerate
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
  let documentRevision: Int64
  let rng: SeededGenerator
  let nodes: [HNSWNode]
  let vectors: [Float]
  let activeDocumentNodes: [UUID: Int]
  let entryPoint: Int?
  let maxLayer: Int

  enum CodingKeys: String, CodingKey {
    case formatVersion
    case dimension
    case config
    case documentRevision
    case rng
    case nodes
    case vectors
    case activeDocumentNodes
    case entryPoint
    case maxLayer
  }

  init(
    formatVersion: Int,
    dimension: Int,
    config: HNSWConfig,
    documentRevision: Int64,
    rng: SeededGenerator,
    nodes: [HNSWNode],
    vectors: [Float],
    activeDocumentNodes: [UUID: Int],
    entryPoint: Int?,
    maxLayer: Int
  ) {
    self.formatVersion = formatVersion
    self.dimension = dimension
    self.config = config
    self.documentRevision = documentRevision
    self.rng = rng
    self.nodes = nodes
    self.vectors = vectors
    self.activeDocumentNodes = activeDocumentNodes
    self.entryPoint = entryPoint
    self.maxLayer = maxLayer
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.formatVersion = try container.decode(Int.self, forKey: .formatVersion)
    self.dimension = try container.decode(Int.self, forKey: .dimension)
    self.config = try container.decode(HNSWConfig.self, forKey: .config)
    self.documentRevision = try container.decodeIfPresent(Int64.self, forKey: .documentRevision) ?? -1
    self.rng = try container.decode(SeededGenerator.self, forKey: .rng)
    self.nodes = try container.decode([HNSWNode].self, forKey: .nodes)
    self.vectors = try container.decode([Float].self, forKey: .vectors)
    self.activeDocumentNodes = try container.decode([UUID: Int].self, forKey: .activeDocumentNodes)
    self.entryPoint = try container.decodeIfPresent(Int.self, forKey: .entryPoint)
    self.maxLayer = try container.decode(Int.self, forKey: .maxLayer)
  }
}

struct HNSWNode: Codable {
  let id: Int
  let documentID: UUID
  let level: Int
  var neighborsByLayer: [[Int]]
  var isDeleted: Bool
}

final class HNSWIndex {
  private let dimension: Int
  private let config: HNSWConfig
  private var rng: SeededGenerator
  private var nodes: [HNSWNode] = []
  private var vectors: [Float] = []
  private var visitedMarks: [UInt32] = []
  private var visitedGeneration: UInt32 = 0
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
    vectors.removeAll(keepingCapacity: true)
    visitedMarks.removeAll(keepingCapacity: true)
    activeDocumentNodes.removeAll(keepingCapacity: true)
    entryPoint = nil
    maxLayer = -1
    rng = SeededGenerator(seed: config.randomSeed)
    reserveCapacity(additionalNodeCount: documents.count)

    for document in orderedForBatchInsertion(documents) {
      try add(documentID: document.id, vector: document.embedding)
    }
  }

  func snapshot(documentRevision: Int64) -> HNSWIndexSnapshot {
    HNSWIndexSnapshot(
      formatVersion: 2,
      dimension: dimension,
      config: config,
      documentRevision: documentRevision,
      rng: rng,
      nodes: nodes,
      vectors: vectors,
      activeDocumentNodes: activeDocumentNodes,
      entryPoint: entryPoint,
      maxLayer: maxLayer
    )
  }

  func restore(from snapshot: HNSWIndexSnapshot) throws {
    guard snapshot.formatVersion == 1 || snapshot.formatVersion == 2 else {
      throw HNSWStorageError.invalidConfiguration("Unsupported HNSW snapshot version")
    }
    guard snapshot.dimension == dimension else {
      throw HNSWStorageError.invalidDimension(expected: dimension, actual: snapshot.dimension)
    }
    guard snapshot.config.m == config.m,
          snapshot.config.level0NeighborMultiplier == config.level0NeighborMultiplier,
          snapshot.config.level0NeighborCap == config.level0NeighborCap,
          snapshot.config.metric == config.metric else {
      throw HNSWStorageError.invalidConfiguration("HNSW snapshot config does not match storage config")
    }
    guard snapshot.vectors.count == snapshot.nodes.count * dimension else {
      throw HNSWStorageError.invalidConfiguration("HNSW snapshot vector buffer is corrupt")
    }

    rng = snapshot.rng
    nodes = snapshot.nodes
    vectors = snapshot.vectors
    visitedMarks = Array(repeating: 0, count: nodes.count)
    visitedGeneration = 0
    activeDocumentNodes = snapshot.activeDocumentNodes
    entryPoint = snapshot.entryPoint
    maxLayer = snapshot.maxLayer

    try validateRestoredTopology()
  }

  func reserveCapacity(additionalNodeCount: Int) {
    guard additionalNodeCount > 0 else {
      return
    }

    nodes.reserveCapacity(nodes.count + additionalNodeCount)
    vectors.reserveCapacity(vectors.count + additionalNodeCount * dimension)
    visitedMarks.reserveCapacity(visitedMarks.count + additionalNodeCount)
    activeDocumentNodes.reserveCapacity(activeDocumentNodes.count + additionalNodeCount)
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
      level: nodeLevel,
      neighborsByLayer: Array(repeating: [], count: nodeLevel + 1),
      isDeleted: false
    )
    nodes.append(node)
    vectors.append(contentsOf: normalizedVector)
    visitedMarks.append(0)
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
        let selected = selectNeighbors(
          candidates: candidates,
          layer: layer,
          queryNodeID: nodeID,
          maxCount: maxNeighbors(for: layer)
        )
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

  func exactSearch(query: [Float], limit: Int) throws -> [UUID] {
    guard limit > 0 else {
      return []
    }

    let normalizedQuery = try VectorScoring.normalized(query, dimension: dimension)
    var topNodes = HNSWScoredNodeHeap(order: .minScore, minimumCapacity: limit)

    normalizedQuery.withUnsafeBufferPointer { queryBuffer in
      vectors.withUnsafeBufferPointer { vectorBuffer in
        guard let queryBase = queryBuffer.baseAddress,
              let vectorBase = vectorBuffer.baseAddress else {
          return
        }

        for nodeID in activeDocumentNodes.values {
          guard nodes.indices.contains(nodeID), !nodes[nodeID].isDeleted else {
            continue
          }
          let candidate = HNSWScoredNode(
            id: nodeID,
            score: score(queryBase: queryBase, vectorBase: vectorBase, nodeID: nodeID)
          )
          if topNodes.count < limit {
            topNodes.insert(candidate)
          } else if let worst = topNodes.peek, candidate.score > worst.score {
            _ = topNodes.popRoot()
            topNodes.insert(candidate)
          }
        }
      }
    }

    return topNodes.unorderedElements
      .sorted { $0.score > $1.score }
      .map { nodes[$0.id].documentID }
  }

  private func randomLevel() -> Int {
    let multiplier = 1.0 / Foundation.log(Double(max(config.m, 2)))
    let value = max(rng.nextUnitDouble(), Double.leastNonzeroMagnitude)
    return Int(-Foundation.log(value) * multiplier)
  }

  private func greedySearch(query: [Float], entryPoint: Int, layer: Int) -> Int {
    query.withUnsafeBufferPointer { queryBuffer in
      vectors.withUnsafeBufferPointer { vectorBuffer in
        guard let queryBase = queryBuffer.baseAddress,
              let vectorBase = vectorBuffer.baseAddress else {
          return entryPoint
        }

        var current = entryPoint
        var currentScore = score(queryBase: queryBase, vectorBase: vectorBase, nodeID: current)
        var changed = true

        while changed {
          changed = false
          for neighborID in neighbors(of: current, layer: layer) {
            let neighborScore = score(queryBase: queryBase, vectorBase: vectorBase, nodeID: neighborID)
            if neighborScore > currentScore {
              current = neighborID
              currentScore = neighborScore
              changed = true
            }
          }
        }

        return current
      }
    }
  }

  private func searchLayer(
    query: [Float],
    entryPoints: [Int],
    ef: Int,
    layer: Int
  ) -> [HNSWScoredNode] {
    query.withUnsafeBufferPointer { queryBuffer in
      vectors.withUnsafeBufferPointer { vectorBuffer in
        guard let queryBase = queryBuffer.baseAddress,
              let vectorBase = vectorBuffer.baseAddress else {
          return []
        }

        let visitGeneration = nextVisitGeneration()
        var candidates = HNSWScoredNodeHeap(order: .maxScore, minimumCapacity: ef)
        var nearest = HNSWScoredNodeHeap(order: .minScore, minimumCapacity: ef)

        for entryPoint in entryPoints {
          guard markVisited(entryPoint, generation: visitGeneration) else {
            continue
          }
          let scored = HNSWScoredNode(
            id: entryPoint,
            score: score(queryBase: queryBase, vectorBase: vectorBase, nodeID: entryPoint)
          )
          candidates.insert(scored)
          nearest.insert(scored)
        }

        while let current = candidates.popRoot() {
          if nearest.count >= ef, let worst = nearest.peek, current.score < worst.score {
            break
          }

          for neighborID in neighbors(of: current.id, layer: layer) where markVisited(
            neighborID,
            generation: visitGeneration
          ) {
            let scored = HNSWScoredNode(
              id: neighborID,
              score: score(queryBase: queryBase, vectorBase: vectorBase, nodeID: neighborID)
            )
            if nearest.count < ef || scored.score > (nearest.peek?.score ?? -.infinity) {
              candidates.insert(scored)
              nearest.insert(scored)

              if nearest.count > ef {
                _ = nearest.popRoot()
              }
            }
          }
        }

        return nearest.unorderedElements.sorted { $0.score > $1.score }
      }
    }
  }

  private func selectNeighbors(
    candidates: [HNSWScoredNode],
    layer: Int,
    queryNodeID: Int,
    maxCount: Int,
    prefiltered: Bool = false
  ) -> [Int] {
    vectors.withUnsafeBufferPointer { vectorBuffer in
      guard let vectorBase = vectorBuffer.baseAddress else {
        return []
      }
      return selectNeighbors(
        candidates: candidates,
        layer: layer,
        queryNodeID: queryNodeID,
        maxCount: maxCount,
        prefiltered: prefiltered,
        vectorBase: vectorBase
      )
    }
  }

  private func selectNeighbors(
    candidates: [HNSWScoredNode],
    layer: Int,
    queryNodeID: Int,
    maxCount: Int,
    prefiltered: Bool,
    vectorBase: UnsafePointer<Float>
  ) -> [Int] {
    var selected: [Int] = []
    var rejected: [Int] = []
    selected.reserveCapacity(maxCount)
    rejected.reserveCapacity(maxCount)

    for candidate in candidates {
      if selected.contains(candidate.id) || rejected.contains(candidate.id) {
        continue
      }
      if !prefiltered && !isSelectableNeighbor(candidate.id, layer: layer, queryNodeID: queryNodeID) {
        continue
      }

      if shouldSelectDiversifiedNeighbor(
        candidateID: candidate.id,
        candidateQueryScore: candidate.score,
        selectedIDs: selected,
        vectorBase: vectorBase
      ) {
        selected.append(candidate.id)
      } else {
        rejected.append(candidate.id)
      }

      if selected.count == maxCount {
        return selected
      }
    }

    for candidateID in rejected {
      selected.append(candidateID)
      if selected.count == maxCount {
        break
      }
    }

    return selected
  }

  private func connect(nodeID: Int, neighbors: [Int], layer: Int) {
    guard nodes[nodeID].neighborsByLayer.indices.contains(layer) else {
      return
    }

    nodes[nodeID].neighborsByLayer[layer] = neighbors
    let maxNeighborCount = maxNeighbors(for: layer)
    for neighborID in neighbors where nodes[neighborID].neighborsByLayer.indices.contains(layer) {
      guard !nodes[neighborID].neighborsByLayer[layer].contains(nodeID) else {
        continue
      }

      nodes[neighborID].neighborsByLayer[layer].append(nodeID)
      if nodes[neighborID].neighborsByLayer[layer].count > maxNeighborCount {
        pruneNeighbors(of: neighborID, layer: layer, maxCount: maxNeighborCount)
      }
    }
  }

  private func pruneNeighbors(of nodeID: Int, layer: Int, maxCount: Int) {
    var candidates: [HNSWScoredNode] = []
    candidates.reserveCapacity(nodes[nodeID].neighborsByLayer[layer].count)

    vectors.withUnsafeBufferPointer { vectorBuffer in
      guard let vectorBase = vectorBuffer.baseAddress else {
        return
      }

      for neighborID in nodes[nodeID].neighborsByLayer[layer] where isSelectableNeighbor(
        neighborID,
        layer: layer,
        queryNodeID: nodeID
      ) {
        candidates.append(
          HNSWScoredNode(
            id: neighborID,
            score: score(vectorBase: vectorBase, nodeID: nodeID, neighborID: neighborID)
          )
        )
      }

      candidates.sort { $0.score > $1.score }
      nodes[nodeID].neighborsByLayer[layer] = selectNeighbors(
        candidates: candidates,
        layer: layer,
        queryNodeID: nodeID,
        maxCount: maxCount,
        prefiltered: true,
        vectorBase: vectorBase
      )
    }
  }

  private func maxNeighbors(for layer: Int) -> Int {
    guard layer == 0 else {
      return config.m
    }

    let scaled = config.m * config.level0NeighborMultiplier
    guard config.level0NeighborCap > 0 else {
      return max(config.m, scaled)
    }
    return max(config.m, min(scaled, config.level0NeighborCap))
  }

  func orderedForBatchInsertion(_ documents: [VecturaDocument]) -> [VecturaDocument] {
    guard let seed = config.batchInsertionSeed, documents.count > 1 else {
      return documents
    }

    var ordered = documents
    var generator = SeededGenerator(seed: seed)
    for index in stride(from: ordered.count - 1, through: 1, by: -1) {
      let swapIndex = Int(generator.next() % UInt64(index + 1))
      ordered.swapAt(index, swapIndex)
    }
    return ordered
  }

  private func isSelectableNeighbor(_ nodeID: Int, layer: Int, queryNodeID: Int) -> Bool {
    guard nodeID != queryNodeID,
          nodes.indices.contains(nodeID),
          nodes[nodeID].neighborsByLayer.indices.contains(layer),
          nodes[nodeID].level >= layer,
          !nodes[nodeID].isDeleted else {
      return false
    }
    return true
  }

  private func shouldSelectDiversifiedNeighbor(
    candidateID: Int,
    candidateQueryScore: Float,
    selectedIDs: [Int],
    vectorBase: UnsafePointer<Float>
  ) -> Bool {
    for selectedID in selectedIDs {
      let candidateToSelectedScore = score(
        vectorBase: vectorBase,
        nodeID: candidateID,
        neighborID: selectedID
      )
      if candidateToSelectedScore >= candidateQueryScore {
        return false
      }
    }
    return true
  }

  private func neighbors(of nodeID: Int, layer: Int) -> [Int] {
    guard nodes.indices.contains(nodeID),
          nodes[nodeID].neighborsByLayer.indices.contains(layer) else {
      return []
    }
    return nodes[nodeID].neighborsByLayer[layer]
  }

  private func validateRestoredTopology() throws {
    guard maxLayer >= -1 else {
      throw HNSWStorageError.invalidConfiguration("HNSW snapshot max layer is corrupt")
    }
    if let entryPoint {
      guard nodes.indices.contains(entryPoint) else {
        throw HNSWStorageError.invalidConfiguration("HNSW snapshot entry point is corrupt")
      }
      guard nodes[entryPoint].level >= maxLayer else {
        throw HNSWStorageError.invalidConfiguration("HNSW snapshot entry point layer is corrupt")
      }
    } else if !nodes.isEmpty {
      throw HNSWStorageError.invalidConfiguration("HNSW snapshot is missing an entry point")
    }

    for (nodeIndex, node) in nodes.enumerated() {
      guard node.id == nodeIndex else {
        throw HNSWStorageError.invalidConfiguration("HNSW snapshot node IDs are corrupt")
      }
      guard node.level >= 0, node.neighborsByLayer.count == node.level + 1 else {
        throw HNSWStorageError.invalidConfiguration("HNSW snapshot node layers are corrupt")
      }

      for (layer, neighbors) in node.neighborsByLayer.enumerated() {
        for neighborID in neighbors {
          guard neighborID != node.id,
                nodes.indices.contains(neighborID),
                nodes[neighborID].neighborsByLayer.indices.contains(layer) else {
            throw HNSWStorageError.invalidConfiguration("HNSW snapshot neighbor links are corrupt")
          }
        }
      }
    }

    for (documentID, nodeID) in activeDocumentNodes {
      guard nodes.indices.contains(nodeID),
            nodes[nodeID].documentID == documentID,
            !nodes[nodeID].isDeleted else {
        throw HNSWStorageError.invalidConfiguration("HNSW snapshot active document map is corrupt")
      }
    }
  }

  private func nextVisitGeneration() -> UInt32 {
    if visitedGeneration == UInt32.max {
      visitedMarks = Array(repeating: 0, count: nodes.count)
      visitedGeneration = 1
    } else {
      visitedGeneration += 1
    }
    return visitedGeneration
  }

  private func markVisited(_ nodeID: Int, generation: UInt32) -> Bool {
    guard visitedMarks.indices.contains(nodeID), visitedMarks[nodeID] != generation else {
      return false
    }

    visitedMarks[nodeID] = generation
    return true
  }

  private func score(
    queryBase: UnsafePointer<Float>,
    vectorBase: UnsafePointer<Float>,
    nodeID: Int
  ) -> Float {
    let offset = nodeID * dimension
    return vDSP.dot(
      UnsafeBufferPointer(start: queryBase, count: dimension),
      UnsafeBufferPointer(start: vectorBase.advanced(by: offset), count: dimension)
    )
  }

  private func score(
    vectorBase: UnsafePointer<Float>,
    nodeID: Int,
    neighborID: Int
  ) -> Float {
    let lhsOffset = nodeID * dimension
    let rhsOffset = neighborID * dimension
    return vDSP.dot(
      UnsafeBufferPointer(start: vectorBase.advanced(by: lhsOffset), count: dimension),
      UnsafeBufferPointer(start: vectorBase.advanced(by: rhsOffset), count: dimension)
    )
  }
}
