# VecturaHNSWKit TODO

## 0.1

- [x] Create package and local git repository.
- [x] Keep roadmap in Markdown for reference.
- [x] Implement `HNSWStorageProvider`.
- [x] Implement in-memory HNSW candidate search.
- [x] Store documents in SQLite.
- [x] Add VecturaKit integration tests.
- [x] Commit 0.1.

## 0.2

- [x] Persist HNSW snapshots.
- [x] Add rebuild and compact APIs.
- [x] Add benchmark executable.
- [x] Compare against plain VecturaKit exact scan.
- [x] Commit 0.2.

## 0.3

- [x] Add recovery policy.
- [x] Add index/document drift checks.
- [x] Add LumoKit-style usage example.
- [x] Commit 0.3.

## 1.0

- [x] Freeze public API names.
- [x] Add final benchmark docs.
- [x] Run full build, test, and benchmark pass.
- [x] Commit 1.0.

## 1.1

- [x] Add exact candidate fallback for small corpora.
- [x] Add bounded topK heap for exact fallback.
- [x] Add automatic tombstone compaction policy.
- [x] Validate snapshots with SQLite document revisions.
- [x] Tune candidate document loading for normal and large ID lists.
- [x] Re-run release benchmarks against plain VecturaKit exact scan.

## 1.2

- [x] Accelerate HNSW vector scoring.
- [x] Reuse visited markers during graph traversal.
- [x] Reserve graph capacity before batch inserts.
- [x] Remove closure-based heap comparison from the hot path.
- [x] Re-run ingestion-focused release benchmarks.

## 1.3

- [x] Research HNSW paper, hnswlib, Faiss, and insertion-order findings.
- [x] Add explicit ground-layer neighbor tuning.
- [x] Keep safe capped ground-layer behavior by default.
- [x] Add optional deterministic batch insertion shuffling.
- [x] Benchmark default, high-recall, uncapped, and seeded-order variants.

## 1.4

- [x] Audit code and docs for inflated or stale claims.
- [x] Reuse vector buffers across graph traversal and neighbor-selection hot paths.
- [x] Prune reverse links only when a layer exceeds its neighbor budget.
- [x] Validate snapshot topology before accepting restored graph state.
- [x] Make benchmark vectors deterministic across processes.
- [x] Re-run release benchmarks against plain VecturaKit exact scan.
