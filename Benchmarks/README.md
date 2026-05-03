# Benchmarks

Run from the repository root:

```sh
swift run -c release vectura-hnsw-benchmark
```

Environment options:

| Variable | Default | Meaning |
| --- | ---: | --- |
| `VECTURA_HNSW_BENCH_DOCS` | `2000` | Number of documents/vectors |
| `VECTURA_HNSW_BENCH_DIM` | `128` | Vector dimension |
| `VECTURA_HNSW_BENCH_QUERIES` | `25` | Query count |
| `VECTURA_HNSW_BENCH_TOPK` | `10` | Requested result count |
| `VECTURA_HNSW_BENCH_CANDIDATE_MULTIPLIER` | `8` | HNSW prefilter multiplier |
| `VECTURA_HNSW_BENCH_M` | `16` | HNSW neighbor count |
| `VECTURA_HNSW_BENCH_LEVEL0_MULTIPLIER` | `2` | Ground-layer neighbor multiplier |
| `VECTURA_HNSW_BENCH_LEVEL0_CAP` | `32` | Ground-layer neighbor cap; use `0` for uncapped |
| `VECTURA_HNSW_BENCH_EF_CONSTRUCTION` | `200` | Insert-time search breadth |
| `VECTURA_HNSW_BENCH_EF_SEARCH` | `128` | Query-time search breadth |
| `VECTURA_HNSW_BENCH_EXACT_THRESHOLD` | `10000` | Document-count threshold for exact candidate fallback |
| `VECTURA_HNSW_BENCH_BATCH_INSERTION_SEED` | unset | Optional deterministic batch insertion shuffle seed |

The benchmark reports:

- exact scan latency
- public VecturaHNSWKit candidate lookup latency
- HNSW-backed VecturaKit latency
- candidate recall@K before exact rescoring
- recall@1
- recall@K
- insert time
- snapshot write time
- cold open time
- snapshot size

The synthetic vectors are generated from stable seeds so repeated release runs
use the same corpus and query set.

See [RESULTS.md](RESULTS.md) and [OPTIMIZATION_RESULTS.md](OPTIMIZATION_RESULTS.md)
for local result snapshots.
