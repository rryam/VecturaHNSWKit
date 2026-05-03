# VecturaHNSWKit Release Checklist

## 1.0.0

- [x] Create package and repository.
- [x] Implement `HNSWStorageProvider`.
- [x] Store documents in SQLite.
- [x] Implement HNSW candidate search.
- [x] Add exact fallback for small corpora.
- [x] Add binary snapshots, recovery policies, rebuild, and compaction APIs.
- [x] Add SQLite revision validation for snapshots.
- [x] Add automatic tombstone compaction controls.
- [x] Add Accelerate-backed vector scoring.
- [x] Add graph construction tuning knobs.
- [x] Make benchmark vectors deterministic across processes.
- [x] Benchmark against plain VecturaKit exact scan.
- [x] Update README, changelog, and benchmark docs.
- [x] Run build and test verification.
- [x] Publish the `1.0.0` tag.
