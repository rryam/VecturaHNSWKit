# LumoKit Usage

LumoKit should stay the RAG workflow layer. VecturaHNSWKit should stay the
indexed vector backend.

The intended composition is:

```swift
import LumoKit
import VecturaEmbeddingsKit
import VecturaHNSWKit
import VecturaKit

let embedder = SwiftEmbedder(modelSource: .default)

let storage = try HNSWStorageProvider(
  directoryURL: databaseURL.appendingPathComponent("hnsw"),
  dimension: 384,
  recoveryPolicy: .validateSnapshotIfAvailable
)

let vecturaConfig = try VecturaConfig(
  name: "knowledge-base",
  directoryURL: databaseURL,
  dimension: 384,
  memoryStrategy: .indexed(candidateMultiplier: 8)
)

let vectura = try await VecturaKit(
  config: vecturaConfig,
  embedder: embedder,
  storageProvider: storage
)
```

If LumoKit exposes a storage-provider initializer, the user-facing flow becomes:

```swift
let lumo = try await LumoKit(
  config: vecturaConfig,
  chunkingConfig: chunkingConfig,
  embedder: embedder,
  storageProvider: storage
)
```

That keeps the stack clean:

```text
LumoKit parses and chunks documents.
VecturaEmbeddingsKit creates vectors.
VecturaKit coordinates storage and search.
VecturaHNSWKit provides indexed candidate search.
```
