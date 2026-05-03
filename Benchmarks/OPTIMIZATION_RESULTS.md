# Optimization Results

Local release-mode benchmark snapshots from May 3, 2026.

Benchmarks are noisy on a developer machine, so compare rows cautiously. The
main signal is the direction after each isolated change.

## High-Recall Preset

Command shape:

```sh
VECTURA_HNSW_BENCH_DOCS=10000 \
VECTURA_HNSW_BENCH_DIM=384 \
VECTURA_HNSW_BENCH_QUERIES=25 \
VECTURA_HNSW_BENCH_CANDIDATE_MULTIPLIER=20 \
VECTURA_HNSW_BENCH_M=32 \
VECTURA_HNSW_BENCH_EF_CONSTRUCTION=400 \
VECTURA_HNSW_BENCH_EF_SEARCH=400 \
swift run -c release vectura-hnsw-benchmark
```

| Step | Plain exact avg ms | HNSW candidate avg ms | Full HNSW avg ms | recall@10 |
| --- | ---: | ---: | ---: | ---: |
| Baseline before perf fixes | 2.449 | n/a | 4.726 | 1.0000 |
| Bounded heaps | 3.179 | n/a | 4.054 | 0.9960 |
| Reused SQLite lookup statement | 2.511 | n/a | 2.940 | 0.9880 |
| Contiguous vector buffer | 2.090 | n/a | 2.662 | 0.9920 |
| Candidate-only benchmark split | 3.278 | 2.012 | 3.483 | 1.0000 |
| Diversified neighbors + capped ground layer | 2.548 | 1.620 | 2.780 | 1.0000 |
| 1.1 exact fallback + bounded topK heap | 2.123 | 1.430 | 1.441 | 1.0000 |
| 1.2 Accelerate scoring + traversal reuse | 2.017 | 0.535 | 0.535 | 1.0000 |

The 1.1 row uses exact candidate fallback at 10K. Since that path already knows
the exact topK, it returns only `topK` candidates for rescoring instead of the
wider graph prefilter set. The 1.2 row keeps the same behavior but moves vector
scoring to Accelerate and reuses traversal bookkeeping during graph construction.

## Larger Corpus Presets

### 25K Speed Preset

```sh
VECTURA_HNSW_BENCH_DOCS=25000 \
VECTURA_HNSW_BENCH_DIM=384 \
VECTURA_HNSW_BENCH_QUERIES=20 \
VECTURA_HNSW_BENCH_CANDIDATE_MULTIPLIER=8 \
swift run -c release vectura-hnsw-benchmark
```

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 6.764 | 6.705 | 6.821 | 8.718 |
| VecturaHNSWKit candidates only | 0.627 | 0.622 | 0.739 | 0.772 |
| VecturaHNSWKit | 1.098 | 1.094 | 1.211 | 1.248 |

```text
candidate recall@10: 0.8400
recall@1: 1.0000
recall@10: 0.8400
plain insert: 2454.980 ms
hnsw insert: 21303.810 ms
```

### 25K Wider-Search Preset

```sh
VECTURA_HNSW_BENCH_DOCS=25000 \
VECTURA_HNSW_BENCH_DIM=384 \
VECTURA_HNSW_BENCH_QUERIES=20 \
VECTURA_HNSW_BENCH_CANDIDATE_MULTIPLIER=20 \
VECTURA_HNSW_BENCH_M=32 \
VECTURA_HNSW_BENCH_EF_CONSTRUCTION=400 \
VECTURA_HNSW_BENCH_EF_SEARCH=400 \
swift run -c release vectura-hnsw-benchmark
```

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 7.106 | 7.186 | 7.500 | 8.724 |
| VecturaHNSWKit candidates only | 1.432 | 1.431 | 1.539 | 1.582 |
| VecturaHNSWKit | 2.753 | 2.766 | 2.888 | 2.902 |

```text
candidate recall@10: 0.9700
recall@1: 1.0000
recall@10: 0.9700
plain insert: 2456.997 ms
hnsw insert: 28058.457 ms
```

Diversified construction, a capped 32-neighbor ground layer, and wider query
breadth improve 25K recall substantially. The tradeoff is slower graph
construction and higher query latency than the speed preset.

## Internet-Informed 1.3 Knobs

The HNSW paper emphasizes the neighbor-selection heuristic for high-recall and
clustered data. hnswlib and Faiss both keep a wider layer-0 graph than upper
layers. Recent HNSW research also shows insertion order can shift recall, so
VecturaHNSWKit now exposes those as explicit build controls instead of hidden
defaults.

### Seeded Batch Insertion

```sh
VECTURA_HNSW_BENCH_DOCS=25000 \
VECTURA_HNSW_BENCH_DIM=384 \
VECTURA_HNSW_BENCH_QUERIES=20 \
VECTURA_HNSW_BENCH_CANDIDATE_MULTIPLIER=8 \
VECTURA_HNSW_BENCH_BATCH_INSERTION_SEED=42 \
swift run -c release vectura-hnsw-benchmark
```

```text
candidate recall@10: 0.8100
recall@10: 0.8100
hnsw insert: 22482.303 ms
```

This synthetic corpus only moved slightly. The knob is mainly for sorted or
clustered bulk loads, where insertion order is known to matter.

### Uncapped Level-0 Width

For `m = 32`, disabling the default `level0NeighborCap` allows a 64-neighbor
ground layer. On the 25K wider-search preset, this reached recall@10 `1.0000`
locally, but insert time rose to `106846.854 ms`. That is why VecturaHNSWKit
keeps the 32-neighbor cap by default and makes uncapped level-0 width explicit.
