import Foundation

enum VectorScoring {
  static func normalized(_ vector: [Float], dimension: Int) throws -> [Float] {
    guard vector.count == dimension else {
      throw HNSWStorageError.invalidDimension(expected: dimension, actual: vector.count)
    }

    var sum: Float = 0
    for value in vector {
      sum += value * value
    }

    guard sum > 0 else {
      return vector
    }

    let norm = sqrt(sum)
    return vector.map { $0 / norm }
  }

  static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
    var score: Float = 0
    for index in lhs.indices {
      score += lhs[index] * rhs[index]
    }
    return score
  }
}
