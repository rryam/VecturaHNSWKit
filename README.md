# VecturaHNSWKit

VecturaHNSWKit adds a real HNSW-backed indexed storage provider for
[VecturaKit](https://github.com/rryam/VecturaKit).

The package is intentionally narrow:

```text
VecturaKit           -> core vector database API
VecturaEmbeddingsKit -> embedding generation
VecturaHNSWKit       -> HNSW indexed storage backend
LumoKit              -> RAG pipeline above the database
```

## Status

This repository is being built in milestone commits:

- `0.1`: SQLite document store plus in-memory HNSW candidate search.
- `0.2`: persisted index snapshot, rebuild/compact APIs, and benchmarks.
- `0.3`: crash recovery policy, examples, and integration docs.
- `1.0`: stable public API and benchmark documentation.

See [ROADMAP.md](ROADMAP.md) and [TODO.md](TODO.md).

## Basic Usage

```swift
import VecturaKit
import VecturaHNSWKit

let storage = try HNSWStorageProvider(
  directoryURL: databaseURL,
  dimension: 384,
  config: .default,
  recoveryPolicy: .validateSnapshotIfAvailable
)

let vectura = try await VecturaKit(
  config: config,
  embedder: embedder,
  storageProvider: storage
)
```

Use `VecturaConfig.MemoryStrategy.indexed` when you want VecturaKit's vector
search path to ask the storage provider for HNSW candidates.

## Benchmarks

Run the benchmark executable in release mode:

```sh
swift run -c release vectura-hnsw-benchmark
```

The benchmark compares only:

```text
Plain VecturaKit exact vector scan
VecturaKit using VecturaHNSWKit indexed storage
```

Useful overrides:

```sh
VECTURA_HNSW_BENCH_DOCS=10000 \
VECTURA_HNSW_BENCH_DIM=384 \
VECTURA_HNSW_BENCH_QUERIES=100 \
swift run -c release vectura-hnsw-benchmark
```

The output includes search latency, recall@K against exact scan, insert time,
snapshot write time, cold open time, and snapshot size.

## Recovery

`HNSWStorageProvider` stores documents in SQLite and stores the HNSW graph as an
optional binary snapshot. The default recovery policy validates the snapshot
against active SQLite documents and rebuilds the graph when the snapshot is
stale.

```swift
let storage = try HNSWStorageProvider(
  directoryURL: databaseURL,
  dimension: 384,
  recoveryPolicy: .validateSnapshotIfAvailable
)

let report = await storage.recoveryReport
```

Use `.loadSnapshotIfAvailable` when startup speed matters more than validation,
or `.rebuildFromDocuments` when you want to ignore snapshots completely.
