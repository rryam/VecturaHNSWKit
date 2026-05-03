# Changelog

## 1.0.0

- Adds `HNSWStorageProvider`, a SQLite-backed `IndexedVecturaStorage`
  implementation for VecturaKit.
- Adds in-memory HNSW graph construction, candidate search, exact fallback for
  small corpora, and Accelerate-backed vector scoring.
- Adds binary index snapshots with SQLite revision validation, startup recovery
  policies, explicit rebuild, and compaction APIs.
- Adds tombstone deletes with automatic compaction controls.
- Adds HNSW build tuning through `m`, `efConstruction`, `efSearch`,
  `level0NeighborMultiplier`, `level0NeighborCap`, and optional deterministic
  batch insertion shuffling.
- Adds release-mode benchmark tooling against plain VecturaKit exact scan, with
  deterministic synthetic vectors and documented local result snapshots.
- Documents package boundaries with VecturaKit, VecturaEmbeddingsKit,
  VecturaMLXKit, and LumoKit.
