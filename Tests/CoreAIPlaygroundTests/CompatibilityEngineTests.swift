import XCTest
@testable import CoreAIPlayground

final class CompatibilityEngineTests: XCTestCase {

    // MARK: Fixtures

    private func host(ram: Double,
                      appleSilicon: Bool = true,
                      osMajor: Int = 27,
                      freeDisk: Double = 500,
                      brand: String = "Apple M3 Pro") -> HostMachine {
        HostMachine(
            brandString: brand,
            isAppleSilicon: appleSilicon,
            physicalMemoryGB: ram,
            totalCPUCores: 12,
            performanceCores: 6,
            efficiencyCores: 6,
            osMajor: osMajor,
            osMinor: 0,
            osVersionString: "macOS \(osMajor).0",
            freeDiskGB: freeDisk,
            modelIdentifier: "Mac15,3",
            metalDeviceName: brand,
            recommendedMaxWorkingSetGB: ram * 0.75
        )
    }

    private func llm(ramGB: Double, sizeMB: Double = 2000, params: Double = 4, minOS: Int = 27) -> ModelSpec {
        ModelSpec(
            id: "test", name: "Test LLM", family: "Test", modality: .languageModel,
            precision: .int4, parametersB: params, downloadSizeMB: sizeMB,
            runtimeRAMGB: ramGB, minOSMajor: minOS, requiresAppleSilicon: true,
            contextTokens: 8192, runtimeLibrary: "CoreAILanguageModels",
            summary: "", sourceURL: nil, tags: [], verified: true
        )
    }

    // MARK: Memory-driven verdict

    func testAmpleMemoryIsRecommended() {
        let result = CompatibilityEngine.evaluate(model: llm(ramGB: 4), on: host(ram: 64))
        XCTAssertEqual(result.verdict, .recommended)
        XCTAssertLessThan(result.memoryUtilization, 0.6)
    }

    func testModestHeadroomIsCapable() {
        // 16 GB → ~12.5 GB available; a 9 GB model ≈ 72% utilization → capable.
        let result = CompatibilityEngine.evaluate(model: llm(ramGB: 9), on: host(ram: 16))
        XCTAssertEqual(result.verdict, .capable)
    }

    func testNearLimitIsTight() {
        // 16 GB → ~12.5 GB available; an 11.5 GB model ≈ 92% → tight.
        let result = CompatibilityEngine.evaluate(model: llm(ramGB: 11.5), on: host(ram: 16))
        XCTAssertEqual(result.verdict, .tight)
    }

    func testOversizedModelIsUnsupported() {
        let result = CompatibilityEngine.evaluate(model: llm(ramGB: 20), on: host(ram: 16))
        XCTAssertEqual(result.verdict, .unsupported)
        XCTAssertTrue(result.memoryUtilization > 1)
    }

    // MARK: Hard blockers

    func testOldOSBlocks() {
        let result = CompatibilityEngine.evaluate(model: llm(ramGB: 2, minOS: 27), on: host(ram: 64, osMajor: 26))
        XCTAssertEqual(result.verdict, .unsupported)
        XCTAssertTrue(result.checks.contains { $0.title == "macOS version" && $0.status == .fail })
    }

    func testIntelBlocksAppleSiliconModel() {
        let result = CompatibilityEngine.evaluate(
            model: llm(ramGB: 2),
            on: host(ram: 64, appleSilicon: false, brand: "Intel Core i9"))
        XCTAssertEqual(result.verdict, .unsupported)
        XCTAssertTrue(result.checks.contains { $0.title == "Apple Silicon" && $0.status == .fail })
    }

    func testInsufficientDiskBlocks() {
        // 2000 MB model needs ~3.9 GB incl. cache; only 2 GB free.
        let result = CompatibilityEngine.evaluate(model: llm(ramGB: 2, sizeMB: 2000),
                                                  on: host(ram: 64, freeDisk: 2))
        XCTAssertEqual(result.verdict, .unsupported)
        XCTAssertTrue(result.checks.contains { $0.title == "Disk space" && $0.status == .fail })
    }

    // MARK: Throughput estimate

    func testLanguageModelProducesThroughputEstimate() {
        let result = CompatibilityEngine.evaluate(model: llm(ramGB: 4, params: 4), on: host(ram: 64))
        XCTAssertNotNil(result.estimatedTokensPerSecond)
        XCTAssertGreaterThan(result.estimatedTokensPerSecond ?? 0, 0)
    }

    func testSmallerModelEstimatesHigherThroughput() {
        let small = CompatibilityEngine.evaluate(model: llm(ramGB: 1, params: 0.6), on: host(ram: 64))
        let large = CompatibilityEngine.evaluate(model: llm(ramGB: 7, params: 8), on: host(ram: 64))
        XCTAssertGreaterThan(small.estimatedTokensPerSecond ?? 0, large.estimatedTokensPerSecond ?? .infinity)
    }
}

final class AppleSiliconDatabaseTests: XCTestCase {

    func testExactMatch() {
        let chip = AppleSiliconDatabase.match(brandString: "Apple M3 Max")
        XCTAssertEqual(chip?.canonicalName, "Apple M3 Max")
        XCTAssertEqual(chip?.tier, .max)
    }

    func testPrefixMatchForUnknownStepping() {
        // An unknown future label should still resolve to a known family by
        // longest-prefix; "Apple M4 Pro" substring wins over "Apple M4".
        let chip = AppleSiliconDatabase.match(brandString: "Apple M4 Pro (future)")
        XCTAssertEqual(chip?.canonicalName, "Apple M4 Pro")
    }

    func testIntelReturnsNil() {
        XCTAssertNil(AppleSiliconDatabase.match(brandString: "Intel Core i7"))
    }

    func testThroughputScalesWithBandwidth() {
        let base = AppleSiliconDatabase.chips.first { $0.canonicalName == "Apple M1" }!
        let max = AppleSiliconDatabase.chips.first { $0.canonicalName == "Apple M1 Max" }!
        XCTAssertGreaterThan(max.relativeLLMThroughput, base.relativeLLMThroughput)
    }
}

final class ModelCatalogTests: XCTestCase {

    func testBundledCatalogLoads() {
        let catalog = ModelCatalog.loadBundled()
        XCTAssertFalse(catalog.models.isEmpty, "catalog.json should load from the module bundle")
        XCTAssertTrue(catalog.models.contains { $0.id == "qwen3-8b" })
    }

    func testEveryModelHasPositiveSizes() {
        for model in ModelCatalog.loadBundled().models {
            XCTAssertGreaterThan(model.downloadSizeMB, 0, "\(model.id) size")
            XCTAssertGreaterThan(model.runtimeRAMGB, 0, "\(model.id) runtime RAM")
        }
    }
}
