import Foundation

/// A single Core AI–compatible model entry.
///
/// Sizes and runtime-memory figures are the heart of this app: every value
/// here is fed into `CompatibilityEngine` and weighed against the host Mac.
/// Entries flagged `verified == false` carry *estimated* specs — the live
/// source of truth is Apple's registry: `uv run coreai.model.registry --list-models`.
struct ModelSpec: Identifiable, Codable, Hashable, Sendable {

    enum Modality: String, Codable, Sendable, CaseIterable {
        case languageModel
        case imageSegmentation
        case embedding
        case speechRecognition
        case imageGeneration
        case vision

        var label: String {
            switch self {
            case .languageModel:     return "Language Model"
            case .imageSegmentation: return "Image Segmentation"
            case .embedding:         return "Embeddings"
            case .speechRecognition: return "Speech Recognition"
            case .imageGeneration:   return "Image Generation"
            case .vision:            return "Vision"
            }
        }

        var symbol: String {
            switch self {
            case .languageModel:     return "text.bubble"
            case .imageSegmentation: return "scribble.variable"
            case .embedding:         return "point.3.connected.trianglepath.dotted"
            case .speechRecognition: return "waveform"
            case .imageGeneration:   return "photo.artframe"
            case .vision:            return "eye"
            }
        }
    }

    /// Weight precision after Core AI optimization (quantization / palettization).
    enum Precision: String, Codable, Sendable {
        case fp16
        case int8
        case int4
        case mixed

        var label: String {
            switch self {
            case .fp16:  return "FP16"
            case .int8:  return "INT8"
            case .int4:  return "INT4 (palettized)"
            case .mixed: return "Mixed"
            }
        }
    }

    let id: String
    let name: String
    let family: String
    let modality: Modality
    let precision: Precision

    /// Parameter count in billions. `nil` for non-parametric / unpublished.
    let parametersB: Double?

    /// On-disk size of the `.aimodel` resource folder, in megabytes.
    let downloadSizeMB: Double

    /// Estimated peak working-set RAM while running, in gigabytes. For LLMs this
    /// is roughly weights + KV cache + runtime overhead at the listed context.
    let runtimeRAMGB: Double

    /// Minimum macOS major version (Core AI ships in 27).
    let minOSMajor: Int

    let requiresAppleSilicon: Bool

    /// Context window in tokens, where applicable.
    let contextTokens: Int?

    /// The Core AI runtime library used to drive this model.
    /// e.g. `CoreAILanguageModels`, `CoreAIImageSegmenter`.
    let runtimeLibrary: String

    let summary: String
    let sourceURL: String?
    let tags: [String]

    /// `true` when specs come straight from Apple's docs / sessions; `false`
    /// when they are reasonable estimates for a known conversion target.
    let verified: Bool

    var downloadSizeGB: Double { downloadSizeMB / 1024.0 }
}
