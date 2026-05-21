import XCTest
@testable import SwiftPDF

@MainActor
final class TemplateStoreTests: XCTestCase {

    /// Isolated UserDefaults so the `hasSeededSample` flag (and any other
    /// per-test state) can't leak across tests or pollute `.standard`.
    private func freshDefaults() -> UserDefaults {
        let suite = "TemplateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func encode(_ template: FormTemplate) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return try e.encode(template)
    }

    // MARK: - Refresh: seeding

    func test_refresh_empty_folder_seeds_sample() async {
        let provider = FakeSyncProvider()
        let store = TemplateStore(provider: provider, defaults: freshDefaults())

        await store.refresh()

        XCTAssertEqual(store.templates.count, 1, "First refresh on empty folder seeds the sample")
        XCTAssertEqual(provider.saveTemplateCalls.count, 1, "Sample uploaded to provider")
        XCTAssertEqual(provider.stored.count, 1, "Provider retains the seeded sample")
    }

    func test_refresh_does_not_reseed_when_flag_set() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hasSeededSample")
        let provider = FakeSyncProvider()
        let store = TemplateStore(provider: provider, defaults: defaults)

        await store.refresh()

        XCTAssertEqual(store.templates.count, 0, "Seed flag prevents re-seed on empty folder")
        XCTAssertEqual(provider.saveTemplateCalls.count, 0)
    }

    // MARK: - Refresh: loading

    func test_refresh_loads_existing_templates() async throws {
        let sample = FormTemplate.makeFreshSample()
        let provider = FakeSyncProvider()
        provider.stored = [
            .init(
                name: "\(sample.id.uuidString).json",
                identifier: "/CustomCase/Templates/\(sample.id.uuidString).json",
                data: try encode(sample)
            )
        ]
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hasSeededSample")
        let store = TemplateStore(provider: provider, defaults: defaults)

        await store.refresh()

        XCTAssertEqual(store.templates.count, 1)
        XCTAssertEqual(store.templates.first?.id, sample.id)
        XCTAssertEqual(store.lastRefreshSkipCount, 0)
    }

    func test_refresh_skips_corrupt_json_and_records_count() async throws {
        let goodSample = FormTemplate.makeFreshSample()
        let provider = FakeSyncProvider()
        provider.stored = [
            .init(
                name: "\(goodSample.id.uuidString).json",
                identifier: "/templates/good.json",
                data: try encode(goodSample)
            ),
            .init(
                name: "bad.json",
                identifier: "/templates/bad.json",
                data: Data("not valid json".utf8)
            )
        ]
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hasSeededSample")
        let store = TemplateStore(provider: provider, defaults: defaults)

        await store.refresh()

        XCTAssertEqual(store.templates.count, 1, "Good template loaded")
        XCTAssertEqual(store.lastRefreshSkipCount, 1, "Corrupt JSON counted in skip total")
    }

    // MARK: - Delete: round-trip identifier (the commit-3 fix)

    func test_delete_uses_round_tripped_identifier_verbatim() async throws {
        // The fake stores identifiers in lowercase to mimic Dropbox's
        // `pathLower` shape. Before commit 3, TemplateStore.delete
        // synthesized "/Templates/<filename>" with the original-case
        // constant — Dropbox tolerated the case mismatch by accident, but
        // a stricter provider (Drive fileId, NAS WebDAV) would reject it.
        let sample = FormTemplate.makeFreshSample()
        let storedIdentifier = "/CUSTOM/Path/\(sample.id.uuidString).json"
        let provider = FakeSyncProvider()
        provider.stored = [
            .init(
                name: "\(sample.id.uuidString).json",
                identifier: storedIdentifier,
                data: try encode(sample)
            )
        ]
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hasSeededSample")
        let store = TemplateStore(provider: provider, defaults: defaults)
        await store.refresh()
        XCTAssertEqual(store.templates.count, 1, "Setup: template loaded")

        try await store.delete(sample)

        XCTAssertEqual(
            provider.deleteTemplateCalls, [storedIdentifier],
            "Delete passes the exact identifier listTemplates returned"
        )
        XCTAssertEqual(store.templates.count, 0, "Template removed from local list")
        XCTAssertEqual(provider.stored.count, 0, "Provider also dropped it")
    }

    func test_delete_throws_when_identifier_missing() async throws {
        let provider = FakeSyncProvider()
        let store = TemplateStore(provider: provider, defaults: freshDefaults())
        // Construct a template the store has never seen. delete() should
        // refuse rather than synthesizing an identifier.
        let stranger = FormTemplate.makeFreshSample()

        do {
            try await store.delete(stranger)
            XCTFail("Expected identifierMissing error")
        } catch TemplateStore.StoreError.identifierMissing {
            // Expected.
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
        XCTAssertEqual(provider.deleteTemplateCalls.count, 0, "Provider not called when identifier missing")
    }

    // MARK: - Save: updates identifier map

    func test_save_records_returned_identifier_for_later_delete() async throws {
        let provider = FakeSyncProvider()
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hasSeededSample")
        let store = TemplateStore(provider: provider, defaults: defaults)
        let template = FormTemplate.makeFreshSample()

        try await store.save(template)
        XCTAssertEqual(store.templates.count, 1)
        XCTAssertEqual(provider.saveTemplateCalls.count, 1)

        // The save() return is recorded internally; deleting should now use
        // that identifier rather than throwing identifierMissing.
        try await store.delete(template)
        XCTAssertEqual(provider.deleteTemplateCalls.count, 1, "Delete after save uses captured identifier")
    }

    // MARK: - Demo mode: no provider calls

    func test_demo_refresh_seeds_in_memory_only() async {
        let provider = FakeSyncProvider()
        let store = TemplateStore(
            provider: provider,
            isDemo: { true },
            defaults: freshDefaults()
        )

        await store.refresh()

        XCTAssertEqual(store.templates.count, 1, "Demo seeds in-memory sample on first refresh")
        XCTAssertEqual(provider.saveTemplateCalls.count, 0, "Demo never hits provider")
        XCTAssertEqual(provider.stored.count, 0)
    }

    func test_demo_save_is_in_memory_only() async throws {
        let provider = FakeSyncProvider()
        let store = TemplateStore(
            provider: provider,
            isDemo: { true },
            defaults: freshDefaults()
        )
        let template = FormTemplate.makeFreshSample()

        try await store.save(template)

        XCTAssertTrue(store.templates.contains(where: { $0.id == template.id }))
        XCTAssertEqual(provider.saveTemplateCalls.count, 0, "Demo save bypasses provider")
    }

    func test_demo_delete_is_in_memory_only() async throws {
        let provider = FakeSyncProvider()
        let store = TemplateStore(
            provider: provider,
            isDemo: { true },
            defaults: freshDefaults()
        )
        let template = FormTemplate.makeFreshSample()
        try await store.save(template)
        XCTAssertEqual(store.templates.count, 1)

        try await store.delete(template)

        XCTAssertEqual(store.templates.count, 0)
        XCTAssertEqual(provider.deleteTemplateCalls.count, 0, "Demo delete bypasses provider")
    }

    // MARK: - resetForDemoExit clears state

    func test_resetForDemoExit_clears_templates_and_identifiers() async throws {
        let provider = FakeSyncProvider()
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hasSeededSample")
        let store = TemplateStore(provider: provider, defaults: defaults)
        try await store.save(FormTemplate.makeFreshSample())
        XCTAssertEqual(store.templates.count, 1)

        store.resetForDemoExit()

        XCTAssertEqual(store.templates.count, 0)
        XCTAssertEqual(store.loadState, .idle)
    }
}
