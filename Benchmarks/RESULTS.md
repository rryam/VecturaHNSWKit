# Benchmark Results

These are local release-mode benchmark snapshots from May 3, 2026. Re-run the
benchmark before publishing numbers.

The benchmark compares only:

```text
Plain VecturaKit exact vector scan
VecturaHNSWKit public candidate lookup
VecturaKit using VecturaHNSWKit indexed storage
```

## Default Small Preset

Command:

```sh
swift run -c release vectura-hnsw-benchmark
```

Configuration:

```text
documents: 2000
dimension: 128
queries: 25
topK: 10
candidateMultiplier: 8
exactSearchThreshold: 10000
```

Result:

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 0.186 | 0.171 | 0.286 | 0.347 |
| VecturaHNSWKit candidates only | 0.092 | 0.091 | 0.098 | 0.126 |
| VecturaHNSWKit | 0.136 | 0.126 | 0.219 | 0.228 |

Recall:

```text
candidate recall@10: 1.0000
recall@1: 1.0000
recall@10: 1.0000
```

At this size, VecturaHNSWKit uses exact candidate fallback instead of graph
traversal. The result is exact recall without paying HNSW query overhead.

## Medium Default Preset

Command:

```sh
VECTURA_HNSW_BENCH_DOCS=10000 \
VECTURA_HNSW_BENCH_DIM=384 \
VECTURA_HNSW_BENCH_QUERIES=25 \
swift run -c release vectura-hnsw-benchmark
```

Configuration:

```text
documents: 10000
dimension: 384
queries: 25
topK: 10
candidateMultiplier: 8
exactSearchThreshold: 10000
```

Result:

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 2.767 | 2.865 | 3.220 | 4.085 |
| VecturaHNSWKit candidates only | 1.647 | 1.546 | 2.182 | 2.328 |
| VecturaHNSWKit | 1.657 | 1.649 | 2.027 | 2.145 |

Recall:

```text
candidate recall@10: 1.0000
recall@1: 1.0000
recall@10: 1.0000
```

This preset is at the default exact fallback threshold, so candidate selection is
exact and recall stays at 1.0.

## Medium High-Recall Preset

Command:

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

Configuration:

```text
documents: 10000
dimension: 384
queries: 25
topK: 10
candidateMultiplier: 20
exactSearchThreshold: 10000
```

Result:

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 2.123 | 2.058 | 2.564 | 3.141 |
| VecturaHNSWKit candidates only | 1.430 | 1.364 | 1.693 | 2.125 |
| VecturaHNSWKit | 1.441 | 1.412 | 1.562 | 1.675 |

Recall:

```text
candidate recall@10: 1.0000
recall@1: 1.0000
recall@10: 1.0000
```

This preset favors recall. At 10K, exact fallback returns the true topK
candidates, so the full indexed path stays faster than plain exact scan while
keeping exact recall.

## 25K Speed Preset

Command:

```sh
VECTURA_HNSW_BENCH_DOCS=25000 \
VECTURA_HNSW_BENCH_DIM=384 \
VECTURA_HNSW_BENCH_QUERIES=20 \
VECTURA_HNSW_BENCH_CANDIDATE_MULTIPLIER=8 \
swift run -c release vectura-hnsw-benchmark
```

Configuration:

```text
documents: 25000
dimension: 384
queries: 20
topK: 10
candidateMultiplier: 8
exactSearchThreshold: 10000
```

Result:

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 9.460 | 9.491 | 10.820 | 13.213 |
| VecturaHNSWKit candidates only | 1.141 | 1.067 | 1.531 | 1.537 |
| VecturaHNSWKit | 1.681 | 1.621 | 2.019 | 2.079 |

Recall:

```text
candidate recall@10: 0.7800
recall@1: 1.0000
recall@10: 0.7800
```

This preset favors speed. The graph path is much faster than exact scan, with
lower recall@10.

## 25K Wider-Search Preset

Command:

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

Configuration:

```text
documents: 25000
dimension: 384
queries: 20
topK: 10
candidateMultiplier: 20
exactSearchThreshold: 10000
```

Result:

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 7.776 | 6.969 | 13.803 | 14.782 |
| VecturaHNSWKit candidates only | 2.515 | 2.545 | 2.722 | 2.750 |
| VecturaHNSWKit | 3.790 | 3.790 | 3.985 | 4.018 |

Recall:

```text
candidate recall@10: 0.9750
recall@1: 1.0000
recall@10: 0.9750
```

This preset spends more graph and candidate-loading work to recover recall while
remaining faster than exact scan on this local run.
