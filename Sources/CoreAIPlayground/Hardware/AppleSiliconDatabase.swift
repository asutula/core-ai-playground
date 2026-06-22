import Foundation

/// Static reference data for Apple Silicon SoCs. We can read total RAM and the
/// brand string directly from the kernel, but GPU-core counts, Neural Engine
/// throughput and memory bandwidth aren't exposed at runtime — so we look them
/// up here by chip name. This is what powers the "hardware fit" story.
struct ChipInfo: Sendable, Hashable {
    let canonicalName: String
    let generation: Int          // 1...5 (M-series)
    let tier: Tier
    let year: Int
    let gpuCores: ClosedRange<Int>
    let neuralEngineTOPS: Double // INT8 TOPS, marketing figure
    let memoryBandwidthGBs: Int
    let maxUnifiedMemoryGB: Int

    enum Tier: String, Sendable {
        case base = "M"
        case pro = "Pro"
        case max = "Max"
        case ultra = "Ultra"
    }

    /// Rough relative on-device LLM throughput vs an M1 base (= 1.0). Combines
    /// memory bandwidth (the usual bottleneck for token generation) and ANE.
    var relativeLLMThroughput: Double {
        (Double(memoryBandwidthGBs) / 68.0) * 0.7 + (neuralEngineTOPS / 11.0) * 0.3
    }
}

enum AppleSiliconDatabase {

    /// Known M-series chips. Ranges/figures are public Apple specs. Newer parts
    /// (M5 family, late 2025+) use best-available figures and may be refined.
    static let chips: [ChipInfo] = [
        // M1
        ChipInfo(canonicalName: "Apple M1",        generation: 1, tier: .base,  year: 2020, gpuCores: 7...8,   neuralEngineTOPS: 11,   memoryBandwidthGBs: 68,  maxUnifiedMemoryGB: 16),
        ChipInfo(canonicalName: "Apple M1 Pro",    generation: 1, tier: .pro,   year: 2021, gpuCores: 14...16, neuralEngineTOPS: 11,   memoryBandwidthGBs: 200, maxUnifiedMemoryGB: 32),
        ChipInfo(canonicalName: "Apple M1 Max",    generation: 1, tier: .max,   year: 2021, gpuCores: 24...32, neuralEngineTOPS: 11,   memoryBandwidthGBs: 400, maxUnifiedMemoryGB: 64),
        ChipInfo(canonicalName: "Apple M1 Ultra",  generation: 1, tier: .ultra, year: 2022, gpuCores: 48...64, neuralEngineTOPS: 22,   memoryBandwidthGBs: 800, maxUnifiedMemoryGB: 128),
        // M2
        ChipInfo(canonicalName: "Apple M2",        generation: 2, tier: .base,  year: 2022, gpuCores: 8...10,  neuralEngineTOPS: 15.8, memoryBandwidthGBs: 100, maxUnifiedMemoryGB: 24),
        ChipInfo(canonicalName: "Apple M2 Pro",    generation: 2, tier: .pro,   year: 2023, gpuCores: 16...19, neuralEngineTOPS: 15.8, memoryBandwidthGBs: 200, maxUnifiedMemoryGB: 32),
        ChipInfo(canonicalName: "Apple M2 Max",    generation: 2, tier: .max,   year: 2023, gpuCores: 30...38, neuralEngineTOPS: 15.8, memoryBandwidthGBs: 400, maxUnifiedMemoryGB: 96),
        ChipInfo(canonicalName: "Apple M2 Ultra",  generation: 2, tier: .ultra, year: 2023, gpuCores: 60...76, neuralEngineTOPS: 31.6, memoryBandwidthGBs: 800, maxUnifiedMemoryGB: 192),
        // M3
        ChipInfo(canonicalName: "Apple M3",        generation: 3, tier: .base,  year: 2023, gpuCores: 8...10,  neuralEngineTOPS: 18,   memoryBandwidthGBs: 100, maxUnifiedMemoryGB: 24),
        ChipInfo(canonicalName: "Apple M3 Pro",    generation: 3, tier: .pro,   year: 2023, gpuCores: 14...18, neuralEngineTOPS: 18,   memoryBandwidthGBs: 150, maxUnifiedMemoryGB: 36),
        ChipInfo(canonicalName: "Apple M3 Max",    generation: 3, tier: .max,   year: 2023, gpuCores: 30...40, neuralEngineTOPS: 18,   memoryBandwidthGBs: 400, maxUnifiedMemoryGB: 128),
        ChipInfo(canonicalName: "Apple M3 Ultra",  generation: 3, tier: .ultra, year: 2025, gpuCores: 60...80, neuralEngineTOPS: 36,   memoryBandwidthGBs: 800, maxUnifiedMemoryGB: 512),
        // M4
        ChipInfo(canonicalName: "Apple M4",        generation: 4, tier: .base,  year: 2024, gpuCores: 8...10,  neuralEngineTOPS: 38,   memoryBandwidthGBs: 120, maxUnifiedMemoryGB: 32),
        ChipInfo(canonicalName: "Apple M4 Pro",    generation: 4, tier: .pro,   year: 2024, gpuCores: 16...20, neuralEngineTOPS: 38,   memoryBandwidthGBs: 273, maxUnifiedMemoryGB: 64),
        ChipInfo(canonicalName: "Apple M4 Max",    generation: 4, tier: .max,   year: 2024, gpuCores: 32...40, neuralEngineTOPS: 38,   memoryBandwidthGBs: 546, maxUnifiedMemoryGB: 128),
        // M5 (2025+, figures provisional)
        ChipInfo(canonicalName: "Apple M5",        generation: 5, tier: .base,  year: 2025, gpuCores: 10...10, neuralEngineTOPS: 45,   memoryBandwidthGBs: 153, maxUnifiedMemoryGB: 32),
        ChipInfo(canonicalName: "Apple M5 Pro",    generation: 5, tier: .pro,   year: 2026, gpuCores: 16...20, neuralEngineTOPS: 45,   memoryBandwidthGBs: 300, maxUnifiedMemoryGB: 64),
        ChipInfo(canonicalName: "Apple M5 Max",    generation: 5, tier: .max,   year: 2026, gpuCores: 32...40, neuralEngineTOPS: 45,   memoryBandwidthGBs: 600, maxUnifiedMemoryGB: 128)
    ]

    /// Best-effort match of a kernel brand string (e.g. "Apple M3 Pro") to a
    /// known chip. Tries an exact match, then the longest prefix match so an
    /// unknown future stepping still resolves to its family.
    static func match(brandString: String) -> ChipInfo? {
        let trimmed = brandString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = chips.first(where: { $0.canonicalName.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact
        }
        return chips
            .filter { trimmed.range(of: $0.canonicalName, options: [.caseInsensitive]) != nil }
            .max(by: { $0.canonicalName.count < $1.canonicalName.count })
    }
}
