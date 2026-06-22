# Core AI Playground

A native SwiftUI desktop app for exploring **Apple Core AI** — the on-device AI
framework Apple introduced at **WWDC 2026** ([developer.apple.com/core-ai](https://developer.apple.com/core-ai/)) —
with a deliberate focus on **model size & hardware requirements vs. the specs of
the Mac you're running on**.

> Core AI is Apple's successor to Core ML for generative, on-device AI: a
> memory-safe Swift API that loads `.aimodel` assets, specializes them
> ahead-of-time for the exact chip/OS, and runs entirely on Apple Silicon with
> no servers or token costs. It ships in **macOS / iOS 27** and requires
> **Xcode 27**.

## What this app does

The app is organized around a **model catalog** and a **hardware-fit analyzer**:

1. **Detects this Mac** — chip (via `sysctl machdep.cpu.brand_string`), unified
   memory, P/E core split, free disk, macOS version, and Metal device. It then
   enriches the chip with reference data (GPU cores, Neural Engine TOPS, memory
   bandwidth, max RAM) it can't read at runtime.
2. **Catalogs Core AI–compatible models** — name, modality, parameter count,
   `.aimodel` download size, estimated runtime working-set RAM, precision,
   context window, and minimum OS.
3. **Scores fit** — the `CompatibilityEngine` weighs each model's footprint
   against the machine and returns a verdict — **Recommended / Capable / Tight /
   Unsupported** — with an itemized breakdown (Apple Silicon, macOS version,
   disk, unified memory headroom) plus a rough tokens/sec estimate derived from
   the chip's memory bandwidth.
4. **Runs models** — an interactive prompt console loads a downloaded `.aimodel`
   resource folder and streams completions through Core AI's
   `CoreAILanguageModel` + Foundation Models' `LanguageModelSession`.

### The hardware-fit model

For each model the engine computes RAM available for inference as
`total − systemReserve` (the reserve scales with RAM, clamped to 3.5–10 GB),
then buckets the model's working set:

| Utilization of available RAM | Verdict |
| --- | --- |
| ≤ 60% | Recommended |
| 60–85% | Capable |
| 85–100% | Tight fit |
| > 100%, wrong OS, Intel, or no disk | Unsupported |

## Architecture

```
Sources/CoreAIPlayground/
├── App/
│   ├── CoreAIPlaygroundApp.swift   @main SwiftUI App
│   └── AppModel.swift              @Observable state: host + catalog + filtering
├── Hardware/
│   ├── HostMachine.swift           sysctl/Metal detection (testable plain data)
│   └── AppleSiliconDatabase.swift  M1–M5 reference specs + brand-string matching
├── Catalog/
│   ├── ModelSpec.swift             model metadata model
│   └── ModelCatalog.swift          loads bundled catalog.json
├── Compatibility/
│   └── CompatibilityEngine.swift   size-vs-hardware scoring (pure, unit-tested)
├── Runner/
│   └── LanguageRunner.swift        Core AI inference, #if canImport guarded
├── UI/                             SwiftUI views (split view, detail, playground)
└── Resources/catalog.json          curated model snapshot
```

`CompatibilityEngine`, `HostMachine`, `AppleSiliconDatabase` and `ModelCatalog`
are free of SwiftUI so they're covered by `Tests/CoreAIPlaygroundTests`.

## Building & running

Requires **macOS 26+** to build the app shell; **Core AI inference requires
macOS 27 + Xcode 27** (where `import CoreAILanguageModels` / `import CoreAI`
resolve).

```bash
# Open in Xcode (recommended)
open Package.swift

# …or from the command line
swift build
swift run CoreAIPlayground

# Tests (catalog + hardware + compatibility logic)
swift test
```

### Graceful degradation

The catalog and the entire hardware-fit analysis work on **any** modern macOS.
Live inference is gated behind `#if canImport(CoreAILanguageModels)` and
`@available(macOS 27, *)`, so on an older toolchain the app still builds and
runs — the Playground pane simply explains what's needed instead of executing.

## Getting model assets

Models are distributed as `.aimodel` files / resource folders. Apple's recipes
live in [`apple/coreai-models`](https://github.com/apple/coreai-models):

```bash
git clone https://github.com/apple/coreai-models.git && cd coreai-models
uv run coreai.model.registry --list-models      # authoritative catalog
# export a recipe → produces a .aimodel resource folder, then "Load .aimodel…"
```

Apps typically ship these via **Background Assets** and compile them
ahead-of-time with `xcrun coreai-build compile MyModel.aimodel --platform macOS`.

## Caveats & honesty

- The bundled `catalog.json` is a **curated snapshot**. Entries marked `est.`
  carry estimated sizes/RAM; only Qwen3-0.6B, Qwen3-8B and SAM 3 have
  Apple-documented figures from WWDC26. The live registry CLI is the source of
  truth.
- M5-family reference specs are provisional.
- Tokens/sec figures are first-order estimates from memory bandwidth, not
  measurements.

## References

- Apple Core AI — https://developer.apple.com/core-ai/
- `apple/coreai-models` — https://github.com/apple/coreai-models
- WWDC26 *Meet Core AI* — https://developer.apple.com/videos/play/wwdc2026/324/
- WWDC26 *Integrate on-device AI models into your app using Core AI* — https://developer.apple.com/videos/play/wwdc2026/326/
- WWDC26 *Dive into Core AI model authoring and optimization* — https://developer.apple.com/videos/play/wwdc2026/325/
