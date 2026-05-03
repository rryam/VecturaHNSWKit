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

The 1.1 row uses exact candidate fallback at 10K. Since that path already knows
the exact topK, it returns only `topK` candidates for rescoring instead of the
wider graph prefilter set.

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
| Plain VecturaKit exact scan | 9.460 | 9.491 | 10.820 | 13.213 |
| VecturaHNSWKit candidates only | 1.141 | 1.067 | 1.531 | 1.537 |
| VecturaHNSWKit | 1.681 | 1.621 | 2.019 | 2.079 |

```text
candidate recall@10: 0.7800
recall@1: 1.0000
recall@10: 0.7800
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
| Plain VecturaKit exact scan | 7.776 | 6.969 | 13.803 | 14.782 |
| VecturaHNSWKit candidates only | 2.515 | 2.545 | 2.722 | 2.750 |
| VecturaHNSWKit | 3.790 | 3.790 | 3.985 | 4.018 |

```text
candidate recall@10: 0.9750
recall@1: 1.0000
recall@10: 0.9750
```

Diversified construction, a capped 32-neighbor ground layer, and wider query
breadth improve 25K recall substantially. The tradeoff is slower graph
construction and higher query latency than the speed preset.
