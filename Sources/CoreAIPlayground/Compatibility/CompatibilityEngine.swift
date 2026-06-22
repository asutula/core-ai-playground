import Foundation

/// Scores how well a `ModelSpec` fits a `HostMachine`. This is the analytical
/// core of the playground: it turns model size + requirements vs. machine specs
/// into a single verdict plus an itemized, human-readable breakdown.
enum CompatibilityEngine {

    enum Verdict: Int, Comparable, Sendable {
        case unsupported   // hard blocker: wrong OS / not Apple Silicon / won't fit
        case tight         // will load but with little headroom; expect pressure
        case capable       // fits with reasonable headroom
        case recommended   // ample headroom, runs comfortably

        static func < (lhs: Verdict, rhs: Verdict) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .unsupported: return "Unsupported"
            case .tight:       return "Tight fit"
            case .capable:     return "Capable"
            case .recommended: return "Recommended"
            }
        }
    }

    enum CheckStatus: Sendable {
        case pass, warn, fail, info
    }

    struct Check: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let status: CheckStatus
        let detail: String
    }

    struct Result: Sendable {
        let verdict: Verdict
        let headline: String
        let checks: [Check]
        /// Fraction of model-available RAM the runtime working set would consume (0...∞).
        let memoryUtilization: Double
        /// Estimated tokens/sec for language models, relative to the host chip. nil otherwise.
        let estimatedTokensPerSecond: Double?
    }

    /// Evaluate a single model against the host.
    static func evaluate(model: ModelSpec, on host: HostMachine) -> Result {
        var checks: [Check] = []
        var hardBlock = false
        var anyWarn = false

        // 1. Apple Silicon requirement
        if model.requiresAppleSilicon && !host.isAppleSilicon {
            checks.append(Check(title: "Apple Silicon",
                                status: .fail,
                                detail: "Core AI runs only on Apple Silicon. This machine reports “\(host.brandString)”."))
            hardBlock = true
        } else {
            checks.append(Check(title: "Apple Silicon",
                                status: .pass,
                                detail: host.chip.map { "\($0.canonicalName) detected." } ?? host.brandString))
        }

        // 2. OS version (Core AI ships in macOS 27)
        if host.osMajor == 0 {
            checks.append(Check(title: "macOS version",
                                status: .info,
                                detail: "OS version unavailable on this host."))
        } else if host.osMajor < model.minOSMajor {
            checks.append(Check(title: "macOS version",
                                status: .fail,
                                detail: "Needs macOS \(model.minOSMajor)+. This Mac runs \(host.osVersionString)."))
            hardBlock = true
        } else {
            checks.append(Check(title: "macOS version",
                                status: .pass,
                                detail: "macOS \(host.osMajor) meets the macOS \(model.minOSMajor)+ requirement."))
        }

        // 3. Disk: download + first-load specialization roughly doubles footprint.
        let diskNeededGB = model.downloadSizeGB * 2.0
        if host.freeDiskGB > 0 && host.freeDiskGB < diskNeededGB {
            checks.append(Check(title: "Disk space",
                                status: .fail,
                                detail: String(format: "Needs ~%.1f GB (download + specialized cache); %.1f GB free.",
                                               diskNeededGB, host.freeDiskGB)))
            hardBlock = true
        } else {
            checks.append(Check(title: "Disk space",
                                status: .pass,
                                detail: String(format: "%.1f GB download; ~%.1f GB incl. cache. Free: %.1f GB.",
                                               model.downloadSizeGB, diskNeededGB, host.freeDiskGB)))
        }

        // 4. Memory — the decisive factor. Compare runtime working set against
        //    RAM available after reserving headroom for the OS.
        let available = host.memoryAvailableForModelGB
        let utilization = available > 0 ? model.runtimeRAMGB / available : .infinity
        let memoryVerdict: Verdict
        let memStatus: CheckStatus
        let memDetail: String

        if model.runtimeRAMGB > available {
            memoryVerdict = .unsupported
            memStatus = .fail
            memDetail = String(format: "Needs ~%.1f GB working set but only ~%.1f GB is free for models (of %.0f GB total). It would not fit.",
                               model.runtimeRAMGB, available, host.physicalMemoryGB)
            hardBlock = true
        } else if utilization > 0.85 {
            memoryVerdict = .tight
            memStatus = .warn
            memDetail = String(format: "Uses ~%.1f GB of ~%.1f GB model-available RAM (%.0f%%). Expect memory pressure with other apps open.",
                               model.runtimeRAMGB, available, utilization * 100)
            anyWarn = true
        } else if utilization > 0.6 {
            memoryVerdict = .capable
            memStatus = .pass
            memDetail = String(format: "Uses ~%.1f GB of ~%.1f GB model-available RAM (%.0f%%). Comfortable.",
                               model.runtimeRAMGB, available, utilization * 100)
        } else {
            memoryVerdict = .recommended
            memStatus = .pass
            memDetail = String(format: "Uses ~%.1f GB of ~%.1f GB model-available RAM (%.0f%%). Plenty of headroom.",
                               model.runtimeRAMGB, available, utilization * 100)
        }
        checks.append(Check(title: "Unified memory", status: memStatus, detail: memDetail))

        // 5. Chip-class performance note for language models.
        var tps: Double? = nil
        if model.modality == .languageModel, let params = model.parametersB {
            let chip = host.chip
            let throughput = chip?.relativeLLMThroughput ?? 1.0
            // Memory-bandwidth-bound estimate: tokens/sec ≈ k * throughput / params.
            tps = max(2.0, (140.0 * throughput) / max(0.3, params))
            let perf = chip.map { "\($0.canonicalName) (~\($0.memoryBandwidthGBs) GB/s, \(formatTOPS($0.neuralEngineTOPS)) ANE)" } ?? "this chip"
            checks.append(Check(title: "Throughput estimate",
                                status: .info,
                                detail: String(format: "~%.0f tokens/sec on %@ — rough estimate from memory bandwidth.", tps!, perf)))
        }

        // Combine.
        let verdict: Verdict
        var headline: String
        if hardBlock {
            verdict = .unsupported
            headline = "Won’t run on this Mac as configured."
        } else {
            verdict = anyWarn ? min(.tight, memoryVerdict) : memoryVerdict
            switch verdict {
            case .recommended: headline = "Runs comfortably on this Mac."
            case .capable:     headline = "Runs well with reasonable headroom."
            case .tight:       headline = "Will run, but with little memory to spare."
            case .unsupported: headline = "Won’t run on this Mac as configured."
            }
        }
        if !host.supportsCoreAI && !hardBlock {
            headline += " (Core AI itself needs macOS 27 — analysis only here.)"
        }

        return Result(verdict: verdict,
                      headline: headline,
                      checks: checks,
                      memoryUtilization: utilization,
                      estimatedTokensPerSecond: tps)
    }

    private static func formatTOPS(_ t: Double) -> String {
        t == t.rounded() ? String(format: "%.0f TOPS", t) : String(format: "%.1f TOPS", t)
    }
}
