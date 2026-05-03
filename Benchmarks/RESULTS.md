# Benchmark Results

These are local release-mode benchmark snapshots from May 3, 2026. Re-run the
benchmark before publishing numbers.

The benchmark compares only:

```text
Plain VecturaKit exact vector scan
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
```

Result:

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 0.178 | 0.173 | 0.183 | 0.326 |
| VecturaHNSWKit | 0.662 | 0.641 | 0.778 | 0.848 |

Recall:

```text
recall@1: 1.0000
recall@10: 1.0000
```

At this size, exact scan is faster. This is expected because VecturaKit exact
scan uses optimized vector math and 2K vectors is still small.

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
```

Result:

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 1.974 | 1.962 | 2.198 | 3.274 |
| VecturaHNSWKit | 1.206 | 1.168 | 1.465 | 1.587 |

Recall:

```text
recall@1: 1.0000
recall@10: 0.8600
```

This preset favors speed. HNSW is faster than exact scan, but recall@10 is lower.

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
```

Result:

| Engine | avg ms | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Plain VecturaKit exact scan | 2.548 | 2.609 | 2.981 | 3.686 |
| VecturaHNSWKit candidates only | 1.620 | 1.631 | 1.801 | 2.112 |
| VecturaHNSWKit | 2.780 | 2.746 | 3.211 | 3.251 |

Recall:

```text
recall@1: 1.0000
recall@10: 1.0000
```

This preset favors recall. HNSW reaches exact recall for this local query set,
while the full indexed path remains slightly slower than exact scan at 10K.
