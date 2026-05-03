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
  config: .default
)

let vectura = try await VecturaKit(
  config: config,
  embedder: embedder,
  storageProvider: storage
)
```

Use `VecturaConfig.MemoryStrategy.indexed` when you want VecturaKit's vector
search path to ask the storage provider for HNSW candidates.
