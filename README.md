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
- `IndexedVecturaStorage` conformance
- SQLite-backed document persistence
- binary HNSW index snapshots
- startup recovery policies
- tombstone deletes and update-as-reinsert behavior
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
  efConstruction: 200,
  efSearch: 128
)
```

The important knobs:

- `m`: maximum graph neighbors per node. Higher values usually improve recall
  and memory use.
- `efConstruction`: insert-time search breadth. Higher values build a better
  graph but slow ingestion.
- `efSearch`: query-time search breadth. Higher values improve recall but slow
  search.
- `candidateMultiplier`: VecturaKit indexed-mode multiplier. The storage layer
  returns `topK * candidateMultiplier` candidates for exact rescoring.

For speed, start with:

```swift
HNSWConfig(m: 16, efConstruction: 200, efSearch: 128)
```

For higher recall, try:

```swift
HNSWConfig(m: 32, efConstruction: 400, efSearch: 400)
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
snapshot when possible, checks it against active SQLite documents, and rebuilds
from SQLite if the snapshot is stale.

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
Plain VecturaKit exact scan avg: 7.850 ms
VecturaHNSWKit candidates only avg: 0.521 ms
VecturaHNSWKit full avg: 1.011 ms
recall@10: 0.6500
```

Local 10K x 384D high-recall preset after optimization:

```text
Plain VecturaKit exact scan avg: 2.090 ms
VecturaHNSWKit full avg: 2.662 ms
recall@10: 0.9920
```

The current story is honest: HNSW can dramatically reduce latency at larger
corpus sizes, but recall depends on graph construction and tuning. See
[Benchmarks/README.md](Benchmarks/README.md),
[Benchmarks/RESULTS.md](Benchmarks/RESULTS.md), and
[Benchmarks/OPTIMIZATION_RESULTS.md](Benchmarks/OPTIMIZATION_RESULTS.md).

## Current Limits

VecturaHNSWKit is useful today, but it is still early indexing infrastructure:

- high-recall search can be slower than exact scan on small corpora
- ingestion is slower than plain VecturaKit because graph construction does real
  work
- deletes are tombstoned and cleaned up through compaction
- graph snapshots are validated against SQLite, but SQLite and the graph are not
  a single transactional unit
- recall at larger sizes needs continued graph-construction work

Those tradeoffs are deliberate for now. The package keeps correctness,
recoverability, and measurable benchmarks ahead of vague performance claims.

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
