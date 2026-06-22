import XCTest
@testable import CoreAIPlayground

final class ModelSpecDecodingTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func decode(_ json: String) throws -> ModelSpec {
        try decoder.decode(ModelSpec.self, from: Data(json.utf8))
    }

    private let base = """
    {
      "id": "x", "name": "X", "family": "F", "modality": "languageModel",
      "precision": "int4", "parametersB": 1.0, "downloadSizeMB": 100,
      "runtimeRAMGB": 1.0, "minOSMajor": 27, "requiresAppleSilicon": true,
      "contextTokens": 4096, "runtimeLibrary": "CoreAILanguageModels",
      "summary": "", "sourceURL": null, "tags": [], "verified": true
    }
    """

    func testDecodesWithoutDownloadFields() throws {
        let spec = try decode(base)
        XCTAssertNil(spec.downloadURL)
        XCTAssertNil(spec.sha256)
    }

    func testDecodesWithDownloadFields() throws {
        let json = """
        {
          "id": "x", "name": "X", "family": "F", "modality": "languageModel",
          "precision": "int4", "parametersB": 1.0, "downloadSizeMB": 100,
          "runtimeRAMGB": 1.0, "minOSMajor": 27, "requiresAppleSilicon": true,
          "contextTokens": 4096, "runtimeLibrary": "CoreAILanguageModels",
          "summary": "", "sourceURL": null, "tags": [], "verified": true,
          "downloadURL": "https://example.com/x.aimodel",
          "sha256": "abc123"
        }
        """
        let spec = try decode(json)
        XCTAssertEqual(spec.downloadURL, "https://example.com/x.aimodel")
        XCTAssertEqual(spec.sha256, "abc123")
    }

    func testBundledCatalogStillDecodesAfterSchemaChange() {
        XCTAssertFalse(ModelCatalog.loadBundled().models.isEmpty)
    }
}

@MainActor
final class ModelDownloadManagerTests: XCTestCase {

    private func spec(id: String) -> ModelSpec {
        ModelSpec(id: id, name: id, family: "F", modality: .languageModel,
                  precision: .int4, parametersB: 1, downloadSizeMB: 100,
                  runtimeRAMGB: 1, minOSMajor: 27, requiresAppleSilicon: true,
                  contextTokens: 4096, runtimeLibrary: "CoreAILanguageModels",
                  summary: "", sourceURL: nil, tags: [], downloadURL: nil,
                  sha256: nil, verified: true)
    }

    func testFreshModelHasNoExistingAssetAndIdlePhase() {
        let manager = ModelDownloadManager()
        let model = spec(id: "unit-test-\(UUID().uuidString)")
        XCTAssertEqual(manager.phase(for: model), .idle)
        XCTAssertNil(manager.existingAsset(for: model))
    }

    func testModelDirectoryIsCreatedAndScopedToID() {
        let manager = ModelDownloadManager()
        let id = "unit-test-\(UUID().uuidString)"
        let dir = manager.modelDirectory(for: spec(id: id))
        XCTAssertTrue(dir.path.contains(id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        try? FileManager.default.removeItem(at: dir) // cleanup
    }

    func testExistingAssetFindsADroppedFile() throws {
        let manager = ModelDownloadManager()
        let model = spec(id: "unit-test-\(UUID().uuidString)")
        let dir = manager.modelDirectory(for: model)
        let asset = dir.appendingPathComponent("weights.aimodel")
        try Data("stub".utf8).write(to: asset)
        XCTAssertEqual(manager.existingAsset(for: model)?.lastPathComponent, "weights.aimodel")
        try? FileManager.default.removeItem(at: dir) // cleanup
    }
}
