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

The candidate-only row shows that the graph lookup can be faster than exact scan
at this size, while full VecturaKit indexed search still pays for candidate
document loading and exact rescoring.

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
| Plain VecturaKit exact scan | 7.956 | 8.200 | 8.878 | 9.288 |
| VecturaHNSWKit candidates only | 0.895 | 0.908 | 1.063 | 1.097 |
| VecturaHNSWKit | 1.476 | 1.470 | 1.719 | 1.749 |

```text
candidate recall@10: 0.7900
recall@1: 1.0000
recall@10: 0.7900
```

### 25K Wider-Search Preset

```sh
VECTURA_HNSW_BENCH_DOCS=25000 \
VECTURA_HNSW_BENCH_DIM=384 \
VECTURA_HNSW_BENCH_QUERIES=20 \
VECTURA_HNSW_BENCH_CANDIDATE_MULTIPLIER=20 \
VECTURA_HNSW_BENCH_EF_SEARCH=256 \
swift run -c release vectura-hnsw-benchmark
```

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 7.908 | 8.177 | 8.707 | 9.449 |
| VecturaHNSWKit candidates only | 1.731 | 1.730 | 1.966 | 2.131 |
| VecturaHNSWKit | 3.013 | 3.109 | 3.252 | 3.373 |

```text
candidate recall@10: 0.8400
recall@1: 1.0000
recall@10: 0.8400
```

Diversified construction plus a capped 32-neighbor ground layer improved 25K
recall substantially. The tradeoff is slower graph construction and a modest
query-time increase from walking more ground-layer edges.
