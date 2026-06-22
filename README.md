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
│   ├── LanguageRunner.swift        Core AI inference, #if canImport guarded
│   ├── ModelDownloadManager.swift  in-app URLSession downloads (progress/resume/SHA-256)
│   └── ModelDownloaderExtension.swift  Background Assets template (opt-in flag)
├── UI/                             SwiftUI views (split view, detail, playground)
└── Resources/catalog.json          curated model snapshot

CoreAIPlayground.xcodeproj          app target (synchronized to Sources/)
Xcode/Info.plist                    app Info.plist (Background Assets keys scaffolded)
Xcode/CoreAIPlayground.entitlements sandbox + network + files entitlements
```

`CompatibilityEngine`, `HostMachine`, `AppleSiliconDatabase` and `ModelCatalog`
are free of SwiftUI so they're covered by `Tests/CoreAIPlaygroundTests`.

## Building & running

There are two ways to build, sharing the **same** `Sources/` via an Xcode
file-system-synchronized group:

| | `CoreAIPlayground.xcodeproj` | `Package.swift` (SPM) |
| --- | --- | --- |
| Sandboxed `.app` bundle | ✅ | — |
| Entitlements (network, files) | ✅ | — |
| In-app `.aimodel` downloads | ✅ | ✅ (no sandbox) |
| Background Assets delivery | ✅ (add extension target) | — |
| `swift test` from CLI | — | ✅ |

```bash
# Full app (recommended): open the project, pick the CoreAIPlayground scheme, Run.
open CoreAIPlayground.xcodeproj

# CLI / tests against the shared sources
open Package.swift          # or: swift build && swift run CoreAIPlayground
swift test                  # catalog + hardware + compatibility + download logic
```

Deployment target is **macOS 26.0**; **Core AI inference requires macOS 27 +
Xcode 27** (where `import CoreAILanguageModels` / `import CoreAI` resolve) and is
gated by `#if canImport(...)`, so the app builds and runs on 26 with everything
except live inference.

### App target & entitlements

`CoreAIPlayground.xcodeproj` produces a sandboxed app (`Xcode/CoreAIPlayground.entitlements`):

- `com.apple.security.app-sandbox`
- `com.apple.security.network.client` — for downloading `.aimodel` assets
- `com.apple.security.files.user-selected.read-write` — for "Load .aimodel…"

Set your **Development Team** in *Signing & Capabilities* on first build.

### Downloading models (in-app)

The Playground tab has an asset row: paste a URL to an exported `.aimodel`
(or it's prefilled from the catalog's `downloadURL` when present) and hit
**Download**. `ModelDownloadManager` (a background-capable `URLSession`) streams
it into the sandbox container — `~/Library/Application Support/<bundle>/Models/<id>/` —
with progress, cancel, resume, and optional SHA-256 verification, then offers
**Load this asset** to hand it to the runtime.

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

Compile them ahead-of-time with
`xcrun coreai-build compile MyModel.aimodel --platform macOS`.

### Production delivery via Background Assets

The in-app downloader runs only while the app is open. For shipping large models
the Apple-recommended path is **Background Assets**, which downloads packs
out-of-process — even before first launch — driven by a hosted manifest.
`Sources/CoreAIPlayground/Runner/ModelDownloaderExtension.swift` is a
ready-to-wire `BADownloaderExtension` template, compiled only behind the
`BACKGROUND_ASSETS_EXTENSION` flag. To activate it:

1. Add a **Background Download** app-extension target; make this class its
   `@main` principal class and add `BACKGROUND_ASSETS_EXTENSION` to its *Active
   Compilation Conditions*.
2. Add the `com.apple.developer.background-assets` entitlement to the app **and**
   the extension (needs a provisioning profile authorizing it). The entitlements
   file has this scaffolded and commented.
3. Add `BAManifestURL` (+ `BAMaxInstallSize`) to `Xcode/Info.plist` — also
   scaffolded and commented — pointing at your hosted manifest.
4. Optionally share a `group.io.textile.CoreAIPlayground` app group so the
   extension can hand finished downloads to the app.

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
