# VecturaHNSWKit Roadmap

This roadmap keeps the package boundary and release plan explicit.

## Package Boundary

```text
VecturaKit              -> core DB API, storage/search protocols, exact fallback
VecturaEmbeddingsKit    -> SwiftEmbedder / model loading / vector generation
VecturaHNSWKit          -> HNSW indexed storage backend
VecturaMLXKit           -> MLX embedding backend
LumoKit                 -> document parsing, chunking, and RAG workflow
```

VecturaHNSWKit depends on VecturaKit. VecturaKit does not depend on
VecturaHNSWKit.

## Version Plan

### 0.1

- Implement `HNSWStorageProvider`.
- Conform to `VecturaStorage` and `IndexedVecturaStorage`.
- Store documents in SQLite.
- Keep the HNSW graph in memory.
- Support tombstone deletes and update-as-delete-plus-insert.
- Add integration tests proving VecturaKit uses the indexed backend.

### 0.2

- Add persisted HNSW snapshots.
- Add rebuild and compact APIs.
- Add benchmark executable comparing VecturaHNSWKit against plain VecturaKit.
- Track recall against exact scan.

### 0.3

- Add crash recovery policy.
- Add startup validation for metadata/index drift.
- Add LumoKit-style usage example.
- Improve docs around deletes, updates, and compaction.

### 1.0

- Freeze the public API.
- Add final benchmark docs.
- Add release checklist and migration notes.
- Keep comparisons scoped to plain VecturaKit exact scan.

## Benchmark Scope

Benchmarks compare against plain VecturaKit exact scan only.

Required dimensions:

- 384D
- 768D

Required corpus sizes:

- 1K
- 10K
- 50K
- 100K

Required metrics:

- recall@10 against exact scan
- p50 / p95 / p99 latency
- cold open time
- index build time
- insert throughput
- memory peak
- index size on disk
