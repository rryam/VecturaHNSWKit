struct SeededGenerator: Codable, Sendable {
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
