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
| Plain VecturaKit exact scan | 0.191 | 0.178 | 0.238 | 0.341 |
| VecturaHNSWKit candidates only | 0.057 | 0.056 | 0.062 | 0.085 |
| VecturaHNSWKit | 0.096 | 0.090 | 0.135 | 0.171 |

Recall:

```text
candidate recall@10: 1.0000
recall@1: 1.0000
recall@10: 1.0000
plain insert: 205.509 ms
hnsw insert: 607.797 ms
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
| Plain VecturaKit exact scan | 1.910 | 1.823 | 2.204 | 3.184 |
| VecturaHNSWKit candidates only | 0.535 | 0.448 | 0.814 | 1.169 |
| VecturaHNSWKit | 0.518 | 0.496 | 0.665 | 0.693 |

Recall:

```text
candidate recall@10: 1.0000
recall@1: 1.0000
recall@10: 1.0000
plain insert: 984.680 ms
hnsw insert: 6452.751 ms
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
| Plain VecturaKit exact scan | 2.017 | 1.933 | 2.417 | 3.209 |
| VecturaHNSWKit candidates only | 0.535 | 0.457 | 0.903 | 1.062 |
| VecturaHNSWKit | 0.535 | 0.511 | 0.636 | 0.800 |

Recall:

```text
candidate recall@10: 1.0000
recall@1: 1.0000
recall@10: 1.0000
plain insert: 977.596 ms
hnsw insert: 7458.837 ms
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
| Plain VecturaKit exact scan | 6.764 | 6.705 | 6.821 | 8.718 |
| VecturaHNSWKit candidates only | 0.627 | 0.622 | 0.739 | 0.772 |
| VecturaHNSWKit | 1.098 | 1.094 | 1.211 | 1.248 |

Recall:

```text
candidate recall@10: 0.8400
recall@1: 1.0000
recall@10: 0.8400
plain insert: 2454.980 ms
hnsw insert: 21303.810 ms
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
| Plain VecturaKit exact scan | 7.106 | 7.186 | 7.500 | 8.724 |
| VecturaHNSWKit candidates only | 1.432 | 1.431 | 1.539 | 1.582 |
| VecturaHNSWKit | 2.753 | 2.766 | 2.888 | 2.902 |

Recall:

```text
candidate recall@10: 0.9700
recall@1: 1.0000
recall@10: 0.9700
plain insert: 2456.997 ms
hnsw insert: 28058.457 ms
```

This preset spends more graph and candidate-loading work to recover recall while
remaining faster than exact scan on this local run.
