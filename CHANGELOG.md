# Changelog

## 1.2.0

- Moves HNSW vector scoring to Accelerate-backed dot products.
- Reuses per-index visited markers during graph traversal instead of allocating a fresh set per layer search.
- Reserves graph, vector, and lookup capacity before batch inserts.
- Replaces closure-based heap comparison in the graph hot path with explicit min/max heap ordering.
- Cuts the local 25K x 384D speed-preset HNSW insert benchmark from ~83s to ~21s.

## 1.1.0

- Adds adaptive exact candidate selection for small corpora.
- Uses a bounded topK heap for exact fallback instead of sorting every vector.
- Adds automatic tombstone compaction controls.
- Tags HNSW snapshots with SQLite document revisions and rebuilds stale snapshots.
- Uses cached point lookup for normal candidate loads and batched SQL for large ID loads.
- Updates benchmark reporting to measure the public candidate path.

## 1.0.0

- Freezes the initial public API:
  - `HNSWStorageProvider`
  - `HNSWConfig`
  - `HNSWMetric`
  - `HNSWIndexStats`
  - `HNSWRecoveryPolicy`
  - `HNSWRecoveryReport`
- Adds release-mode benchmark executable against plain VecturaKit exact scan.
- Adds benchmark documentation and local result snapshots.
- Adds recovery docs and LumoKit composition notes.

## 0.3.0

- Adds explicit recovery policies.
- Adds snapshot validation against active SQLite documents.
- Adds LumoKit-style usage documentation.

## 0.2.0

- Adds binary HNSW snapshots.
- Adds rebuild and compaction APIs.
- Adds benchmark executable.

## 0.1.0

- Adds SQLite-backed `HNSWStorageProvider`.
- Adds in-memory HNSW candidate search.
- Conforms to `IndexedVecturaStorage`.
- Adds initial VecturaKit integration tests.
