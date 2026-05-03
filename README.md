# VecturaHNSWKit

HNSW indexed vector storage for [VecturaKit](https://github.com/rryam/VecturaKit).

VecturaHNSWKit is the high-performance indexing layer for VecturaKit. It gives
VecturaKit a real HNSW-backed `IndexedVecturaStorage` implementation, with
SQLite document storage, binary index snapshots, recovery policies, compaction,
and benchmark tooling against plain VecturaKit exact scan.

Use it when exact vector scan is no longer the right default for your corpus.

## Why It Exists

Plain VecturaKit is intentionally simple: it can store vectors and search them
exactly. That is a good default for small and medium datasets because exact scan
is predictable, dependency-light, and surprisingly fast.

At larger sizes, exact scan does more work than necessary. HNSW changes the
shape of search from:

```text
compare the query against every vector
```

to:

```text
walk a nearest-neighbor graph and inspect the most promising candidates
```

VecturaHNSWKit adds that indexed path without making VecturaKit itself heavier.

## Package Boundary

```text
VecturaKit              -> core database API, storage protocols, exact fallback
VecturaEmbeddingsKit    -> local embedding generation
VecturaHNSWKit          -> HNSW indexed storage backend
VecturaMLXKit           -> MLX embedding backend
LumoKit                 -> document parsing, chunking, and RAG workflows
```

VecturaHNSWKit depends on VecturaKit. VecturaKit does not depend on
VecturaHNSWKit.

## Features

- HNSW candidate search for VecturaKit indexed mode
- adaptive exact candidate selection for small corpora
- Accelerate-backed vector scoring for graph construction and search
- `IndexedVecturaStorage` conformance
- SQLite-backed document persistence
- binary HNSW index snapshots with SQLite revision validation
- startup recovery policies
- tombstone deletes with automatic compaction controls
- rebuild and compaction APIs
- benchmark executable against plain VecturaKit exact scan
- pure Swift package with a small public API

## Installation

Add VecturaHNSWKit to your package:

```swift
dependencies: [
  .package(url: "https://github.com/rryam/VecturaHNSWKit.git", from: "1.0.0"),
]
```

Then add the product to your target:

```swift
.target(
  name: "App",
  dependencies: [
    .product(name: "VecturaKit", package: "VecturaKit"),
    .product(name: "VecturaHNSWKit", package: "VecturaHNSWKit"),
  ]
)
```

## Quick Start

```swift
import VecturaKit
import VecturaHNSWKit

let storage = try HNSWStorageProvider(
  directoryURL: databaseURL.appendingPathComponent("hnsw"),
  dimension: 384,
  config: .default,
  recoveryPolicy: .validateSnapshotIfAvailable
)

let config = try VecturaConfig(
  name: "knowledge-base",
  directoryURL: databaseURL,
  dimension: 384,
  memoryStrategy: .indexed(candidateMultiplier: 8)
)

let vectura = try await VecturaKit(
  config: config,
  embedder: embedder,
  storageProvider: storage
)

_ = try await vectura.addDocuments(texts: documents)

let results = try await vectura.search(
  query: .vector(queryEmbedding),
  numResults: 10
)
```

VecturaKit still owns the database-facing API. VecturaHNSWKit supplies the
storage backend that can answer `searchVectorCandidates(...)` quickly.

## Configuration

```swift
let hnswConfig = try HNSWConfig(
  m: 16,
  level0NeighborMultiplier: 2,
  level0NeighborCap: 32,
  efConstruction: 200,
  efSearch: 128,
  exactSearchThreshold: 10_000,
  automaticCompactionDeletedRatio: 0.30,
  automaticCompactionMinimumDeletedCount: 1_000,
  batchInsertionSeed: nil
)
```

The important knobs:

- `m`: upper-layer graph neighbors per node. The ground layer keeps a wider
  budget controlled by `level0NeighborMultiplier` and `level0NeighborCap`.
- `level0NeighborMultiplier`: multiplier for the ground-layer neighbor budget.
  The default `2` matches common HNSW practice for a wider base layer.
- `level0NeighborCap`: cap for the ground-layer budget. The default `32`
  preserves fast ingestion; set it to `0` to allow uncapped `m *
  level0NeighborMultiplier` when you explicitly want a heavier recall build.
- `efConstruction`: insert-time search breadth. Higher values build a better
  graph but slow ingestion.
- `efSearch`: query-time search breadth. Higher values improve recall but slow
  search.
- `exactSearchThreshold`: document-count threshold where VecturaHNSWKit uses
  exact in-memory candidate selection instead of graph traversal. The default
  keeps small corpora fast and exact.
- `automaticCompactionDeletedRatio`: deleted-node ratio that triggers automatic
  graph compaction.
- `automaticCompactionMinimumDeletedCount`: minimum tombstone count before
  automatic compaction can run.
- `batchInsertionSeed`: optional deterministic shuffle seed for bulk inserts.
  Use it when the input is sorted or clustered and you want to reduce
  insertion-order sensitivity.
- `candidateMultiplier`: VecturaKit indexed-mode multiplier. Graph search uses
  it to return `topK * candidateMultiplier` candidates for exact rescoring;
  exact fallback returns `topK` because it has already selected exact neighbors.

For speed, start with:

```swift
HNSWConfig(m: 16, efConstruction: 200, efSearch: 128)
```

For higher recall, try:

```swift
HNSWConfig(m: 32, efConstruction: 400, efSearch: 400)
```

For a heavier recall-oriented build that follows the uncapped `2 * m`
ground-layer shape used by mature HNSW implementations:

```swift
HNSWConfig(
  m: 32,
  level0NeighborMultiplier: 2,
  level0NeighborCap: 0,
  efConstruction: 400,
  efSearch: 400
)
```

## Persistence And Recovery

Documents are stored in SQLite. The HNSW graph can be persisted as a binary
snapshot.

```swift
try await storage.saveIndexSnapshot()
try await storage.rebuildIndex()
try await storage.compactIndex()
```

The default recovery policy is `.validateSnapshotIfAvailable`. It loads the
snapshot when possible, checks its SQLite document revision and active document
IDs, and rebuilds from SQLite if the snapshot is stale.

```swift
let storage = try HNSWStorageProvider(
  directoryURL: databaseURL,
  dimension: 384,
  recoveryPolicy: .validateSnapshotIfAvailable
)

let report = await storage.recoveryReport
```

Available policies:

- `.validateSnapshotIfAvailable`: safe default
- `.loadSnapshotIfAvailable`: faster startup, no validation
- `.rebuildFromDocuments`: ignore snapshots and rebuild from SQLite

## Benchmarks

Run the benchmark executable in release mode:

```sh
swift run -c release vectura-hnsw-benchmark
```

The benchmark compares:

```text
Plain VecturaKit exact vector scan
VecturaHNSWKit candidate lookup
VecturaKit using VecturaHNSWKit indexed storage
```

Example:

```sh
VECTURA_HNSW_BENCH_DOCS=25000 \
VECTURA_HNSW_BENCH_DIM=384 \
VECTURA_HNSW_BENCH_QUERIES=20 \
VECTURA_HNSW_BENCH_CANDIDATE_MULTIPLIER=8 \
swift run -c release vectura-hnsw-benchmark
```

Local 25K x 384D speed preset:

```text
Plain VecturaKit exact scan avg: 8.101 ms
VecturaHNSWKit candidates only avg: 0.839 ms
VecturaHNSWKit full avg: 1.214 ms
recall@10: 0.7950
hnsw insert: 21805.923 ms
```

Local 10K x 384D high-recall preset:

```text
Plain VecturaKit exact scan avg: 2.324 ms
VecturaHNSWKit candidates only avg: 0.576 ms
VecturaHNSWKit full avg: 0.682 ms
recall@10: 1.0000
hnsw insert: 6809.994 ms
```

Local 25K x 384D wider-search preset:

```text
Plain VecturaKit exact scan avg: 8.199 ms
VecturaHNSWKit candidates only avg: 1.515 ms
VecturaHNSWKit full avg: 2.894 ms
recall@10: 0.9550
hnsw insert: 29643.618 ms
```

The benchmark story is deliberately measurable: small corpora use exact
candidate selection, larger corpora use the graph, and recall is reported
instead of implied. See
[Benchmarks/README.md](Benchmarks/README.md),
[Benchmarks/RESULTS.md](Benchmarks/RESULTS.md), and
[Benchmarks/OPTIMIZATION_RESULTS.md](Benchmarks/OPTIMIZATION_RESULTS.md).

## Production Behavior

VecturaHNSWKit treats SQLite as the source of truth and the HNSW graph as a
recoverable acceleration structure.

- Small corpora use exact candidate selection by default, backed by a bounded
  topK heap, so indexed mode does not pay graph traversal overhead too early.
- Larger corpora use HNSW graph traversal. Tune `m`, `efConstruction`,
  `efSearch`, and VecturaKit's `candidateMultiplier` based on the latency/recall
  target you need.
- Deletes are tombstoned for fast writes and compact automatically once the
  configured deleted-node threshold is reached. `compactIndex()` is still
  available for explicit maintenance.
- Snapshots carry the SQLite document revision. Validated recovery rejects stale
  snapshots after inserts, deletes, or updates, then rebuilds from SQLite.
- Ingestion is the cost center: graph construction does neighbor search,
  diversified link selection, and reverse-link maintenance. The hot path avoids
  unnecessary reverse-link pruning, but higher `m` and `efConstruction` values
  still deliberately spend build time to buy recall.

The package is built to make these tradeoffs explicit: correctness and
recoverability first, with benchmarks for every performance claim.

## Public API

The public API is intentionally small:

- `HNSWStorageProvider`
- `HNSWConfig`
- `HNSWMetric`
- `HNSWIndexStats`
- `HNSWRecoveryPolicy`
- `HNSWRecoveryReport`
- `VecturaHNSWKitVersion`

## Related Packages

- [VecturaKit](https://github.com/rryam/VecturaKit): core vector database API
- [VecturaEmbeddingsKit](https://github.com/rryam/VecturaEmbeddingsKit): local
  embedding generation
- [VecturaMLXKit](https://github.com/rryam/VecturaMLXKit): MLX embedding backend
- LumoKit: document parsing, chunking, and RAG workflows
