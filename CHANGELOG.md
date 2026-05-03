# Changelog

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
