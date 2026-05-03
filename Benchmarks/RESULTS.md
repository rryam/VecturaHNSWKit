# Benchmark Results

These are local release-mode benchmark snapshots from May 3, 2026. Re-run the
benchmark before publishing numbers. The synthetic vectors use a stable seed so
the corpus is reproducible across benchmark processes.

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
level0NeighborMultiplier: 2
level0NeighborCap: 32
batchInsertionSeed: nil
```

Result:

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 0.211 | 0.187 | 0.408 | 0.424 |
| VecturaHNSWKit candidates only | 0.067 | 0.054 | 0.134 | 0.157 |
| VecturaHNSWKit | 0.100 | 0.092 | 0.122 | 0.215 |

Recall:

```text
candidate recall@10: 1.0000
recall@1: 1.0000
recall@10: 1.0000
plain insert: 208.035 ms
hnsw insert: 353.350 ms
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
level0NeighborMultiplier: 2
level0NeighborCap: 32
batchInsertionSeed: nil
```

Result:

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 2.360 | 2.269 | 2.752 | 3.337 |
| VecturaHNSWKit candidates only | 0.549 | 0.464 | 0.795 | 1.284 |
| VecturaHNSWKit | 0.552 | 0.515 | 0.721 | 0.746 |

Recall:

```text
candidate recall@10: 1.0000
recall@1: 1.0000
recall@10: 1.0000
plain insert: 973.520 ms
hnsw insert: 5417.022 ms
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
level0NeighborMultiplier: 2
level0NeighborCap: 32
batchInsertionSeed: nil
```

Result:

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 2.324 | 2.238 | 2.831 | 3.471 |
| VecturaHNSWKit candidates only | 0.576 | 0.501 | 1.091 | 1.186 |
| VecturaHNSWKit | 0.682 | 0.614 | 1.086 | 1.200 |

Recall:

```text
candidate recall@10: 1.0000
recall@1: 1.0000
recall@10: 1.0000
plain insert: 977.458 ms
hnsw insert: 6809.994 ms
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
level0NeighborMultiplier: 2
level0NeighborCap: 32
batchInsertionSeed: nil
```

Result:

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 8.101 | 8.301 | 8.861 | 10.118 |
| VecturaHNSWKit candidates only | 0.839 | 0.843 | 1.183 | 1.199 |
| VecturaHNSWKit | 1.214 | 1.207 | 1.436 | 1.457 |

Recall:

```text
candidate recall@10: 0.7950
recall@1: 1.0000
recall@10: 0.7950
plain insert: 2452.324 ms
hnsw insert: 21805.923 ms
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
level0NeighborMultiplier: 2
level0NeighborCap: 32
batchInsertionSeed: nil
```

Result:

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 8.199 | 8.187 | 8.650 | 9.834 |
| VecturaHNSWKit candidates only | 1.515 | 1.523 | 1.731 | 1.975 |
| VecturaHNSWKit | 2.894 | 2.953 | 3.110 | 3.262 |

Recall:

```text
candidate recall@10: 0.9550
recall@1: 1.0000
recall@10: 0.9550
plain insert: 2594.359 ms
hnsw insert: 29643.618 ms
```

This preset spends more graph and candidate-loading work to recover recall while
remaining faster than exact scan on this local run.
