enum HNSWScoredNodeHeapOrder {
  case maxScore
  case minScore
}

struct HNSWScoredNodeHeap {
  private var elements: [HNSWScoredNode] = []
  private let order: HNSWScoredNodeHeapOrder

  init(order: HNSWScoredNodeHeapOrder, minimumCapacity: Int = 0) {
    self.order = order
    elements.reserveCapacity(minimumCapacity)
  }

  var count: Int {
    elements.count
  }

  var isEmpty: Bool {
    elements.isEmpty
  }

  var peek: HNSWScoredNode? {
    elements.first
  }

  var unorderedElements: [HNSWScoredNode] {
    elements
  }

  mutating func insert(_ element: HNSWScoredNode) {
    elements.append(element)
    siftUp(from: elements.count - 1)
  }

  mutating func popRoot() -> HNSWScoredNode? {
    guard !elements.isEmpty else {
      return nil
    }
    guard elements.count > 1 else {
      return elements.removeLast()
    }

    let root = elements[0]
    elements[0] = elements.removeLast()
    siftDown(from: 0)
    return root
  }

  private mutating func siftUp(from index: Int) {
    var child = index
    var parent = parentIndex(of: child)

    while child > 0 && hasHigherPriority(elements[child], elements[parent]) {
      elements.swapAt(child, parent)
      child = parent
      parent = parentIndex(of: child)
    }
  }

  private mutating func siftDown(from index: Int) {
    var parent = index

    while true {
      let left = leftChildIndex(of: parent)
      let right = rightChildIndex(of: parent)
      var candidate = parent

      if left < elements.count && hasHigherPriority(elements[left], elements[candidate]) {
        candidate = left
      }
      if right < elements.count && hasHigherPriority(elements[right], elements[candidate]) {
        candidate = right
      }
      if candidate == parent {
        return
      }

      elements.swapAt(parent, candidate)
      parent = candidate
    }
  }

  private func parentIndex(of index: Int) -> Int {
    (index - 1) / 2
  }

  private func leftChildIndex(of index: Int) -> Int {
    index * 2 + 1
  }

  private func rightChildIndex(of index: Int) -> Int {
    index * 2 + 2
  }

  private func hasHigherPriority(_ lhs: HNSWScoredNode, _ rhs: HNSWScoredNode) -> Bool {
    switch order {
    case .maxScore:
      lhs.score > rhs.score
    case .minScore:
      lhs.score < rhs.score
    }
  }
}
