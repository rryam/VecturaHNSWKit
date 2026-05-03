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
| Plain VecturaKit exact scan | 7.850 | 8.009 | 8.681 | 9.633 |
| VecturaHNSWKit candidates only | 0.521 | 0.485 | 0.710 | 0.714 |
| VecturaHNSWKit | 1.011 | 1.000 | 1.167 | 1.240 |

```text
candidate recall@10: 0.6500
recall@1: 1.0000
recall@10: 0.6500
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
| Plain VecturaKit exact scan | 7.656 | 7.818 | 8.351 | 10.920 |
| VecturaHNSWKit candidates only | 1.011 | 1.006 | 1.115 | 1.322 |
| VecturaHNSWKit | 2.243 | 2.181 | 2.602 | 2.685 |

```text
candidate recall@10: 0.6450
recall@1: 0.9500
recall@10: 0.6450
```

The wider search did not recover recall at 25K, which suggests the next recall
work should focus on graph construction and neighbor diversity, not only query
search breadth.
