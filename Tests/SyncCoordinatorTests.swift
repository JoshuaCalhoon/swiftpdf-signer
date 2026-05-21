import XCTest
@testable import SwiftPDF

/// Tests for `SyncCoordinator.authState` composition and the demo-session
/// lifecycle. The composition mapper is exercised exhaustively over the
/// (isDemo × DropboxSyncProvider.AuthState?) cross-product so a future
/// case-addition on the provider side that's not propagated through the
/// switch is caught at compile time (Swift exhaustive switch) plus at test
/// time (this file's expectations).
@MainActor
final class SyncCoordinatorTests: XCTestCase {

    /// `ManagerGate.demoBypass` is global static state — reset between tests
    /// so demo-lifecycle assertions aren't contaminated by sibling test
    /// ordering.
    override func setUp() async throws {
        try await super.setUp()
        ManagerGate.demoBypass = false
    }

    override func tearDown() async throws {
        ManagerGate.demoBypass = false
        try await super.tearDown()
    }

    // MARK: - composeAuthState: pure mapping

    func test_compose_isDemo_true_returns_demo_regardless_of_dropboxState() {
        // Demo takes precedence — even an authorized Dropbox session reads as
        // .demo when isDemo is set. beginDemoSession() refuses to enter demo
        // while a real authorization is in flight, but the mapper itself
        // must be total: any (isDemo=true, dropboxState=X) yields .demo.
        XCTAssertEqual(
            SyncCoordinator.composeAuthState(isDemo: true, dropboxState: nil),
            .demo
        )
        XCTAssertEqual(
            SyncCoordinator.composeAuthState(isDemo: true, dropboxState: .notAuthorized),
            .demo
        )
        XCTAssertEqual(
            SyncCoordinator.composeAuthState(isDemo: true, dropboxState: .authorizing),
            .demo
        )
        XCTAssertEqual(
            SyncCoordinator.composeAuthState(isDemo: true, dropboxState: .authorized),
            .demo
        )
        XCTAssertEqual(
            SyncCoordinator.composeAuthState(isDemo: true, dropboxState: .authFailed(message: "x")),
            .demo
        )
    }

    func test_compose_no_dropbox_maps_to_notAuthorized() {
        XCTAssertEqual(
            SyncCoordinator.composeAuthState(isDemo: false, dropboxState: nil),
            .notAuthorized
        )
    }

    func test_compose_dropbox_notAuthorized_maps_through() {
        XCTAssertEqual(
            SyncCoordinator.composeAuthState(isDemo: false, dropboxState: .notAuthorized),
            .notAuthorized
        )
    }

    func test_compose_dropbox_authorizing_maps_through() {
        XCTAssertEqual(
            SyncCoordinator.composeAuthState(isDemo: false, dropboxState: .authorizing),
            .authorizing
        )
    }

    func test_compose_dropbox_authorized_maps_through() {
        XCTAssertEqual(
            SyncCoordinator.composeAuthState(isDemo: false, dropboxState: .authorized),
            .authorized
        )
    }

    func test_compose_dropbox_authFailed_carries_message_through() {
        // The message field is load-bearing — it surfaces to ConnectDropboxView
        // as the error banner. The mapper must propagate it verbatim.
        let message = "Network connection lost during OAuth"
        XCTAssertEqual(
            SyncCoordinator.composeAuthState(isDemo: false, dropboxState: .authFailed(message: message)),
            .authFailed(message: message)
        )
    }

    // MARK: - Demo-session lifecycle (integration via testing init)

    func test_init_with_test_provider_starts_notAuthorized() {
        let provider = FakeSyncProvider()
        let coordinator = SyncCoordinator(testingProvider: provider)

        XCTAssertFalse(coordinator.isDemo)
        XCTAssertEqual(coordinator.authState, .notAuthorized)
    }

    func test_beginDemoSession_with_no_dropbox_enters_demo_and_sets_bypass() {
        let provider = FakeSyncProvider()
        let coordinator = SyncCoordinator(testingProvider: provider)

        coordinator.beginDemoSession()

        XCTAssertTrue(coordinator.isDemo)
        XCTAssertEqual(coordinator.authState, .demo)
        XCTAssertTrue(
            ManagerGate.demoBypass,
            "Demo session must set ManagerGate.demoBypass so the reviewer can reach Settings / Manage / Disconnect without Face ID"
        )
    }

    func test_endDemoSession_restores_state_and_clears_bypass() {
        let provider = FakeSyncProvider()
        let coordinator = SyncCoordinator(testingProvider: provider)
        coordinator.beginDemoSession()
        XCTAssertTrue(coordinator.isDemo)

        coordinator.endDemoSession()

        XCTAssertFalse(coordinator.isDemo)
        XCTAssertEqual(coordinator.authState, .notAuthorized)
        XCTAssertFalse(ManagerGate.demoBypass)
    }

    func test_endDemoSession_when_not_in_demo_is_noop() {
        let provider = FakeSyncProvider()
        let coordinator = SyncCoordinator(testingProvider: provider)
        // Set a sentinel on the bypass to verify endDemoSession doesn't
        // touch it when it wasn't the one that set it.
        ManagerGate.demoBypass = true

        coordinator.endDemoSession()

        XCTAssertFalse(coordinator.isDemo)
        XCTAssertTrue(
            ManagerGate.demoBypass,
            "endDemoSession is a no-op when isDemo is already false — must not silently flip the bypass off"
        )
    }

    func test_beginDemoSession_followed_by_endDemoSession_roundtrip() {
        let provider = FakeSyncProvider()
        let coordinator = SyncCoordinator(testingProvider: provider)

        for _ in 0..<3 {
            coordinator.beginDemoSession()
            XCTAssertTrue(coordinator.isDemo)
            XCTAssertEqual(coordinator.authState, .demo)
            XCTAssertTrue(ManagerGate.demoBypass)

            coordinator.endDemoSession()
            XCTAssertFalse(coordinator.isDemo)
            XCTAssertEqual(coordinator.authState, .notAuthorized)
            XCTAssertFalse(ManagerGate.demoBypass)
        }
    }

    // MARK: - CRUD forwarders short-circuit in demo

    func test_uploadSigned_in_demo_throws_demoMode() async {
        let provider = FakeSyncProvider()
        let coordinator = SyncCoordinator(testingProvider: provider)
        coordinator.beginDemoSession()

        do {
            _ = try await coordinator.uploadSigned(Data(), filename: "test.pdf")
            XCTFail("Expected SyncError.demoMode")
        } catch SyncError.demoMode {
            // Expected.
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_listTemplates_in_demo_throws_demoMode() async {
        let provider = FakeSyncProvider()
        let coordinator = SyncCoordinator(testingProvider: provider)
        coordinator.beginDemoSession()

        do {
            _ = try await coordinator.listTemplates()
            XCTFail("Expected SyncError.demoMode")
        } catch SyncError.demoMode {
            // Expected.
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_saveTemplate_in_demo_throws_demoMode() async {
        let provider = FakeSyncProvider()
        let coordinator = SyncCoordinator(testingProvider: provider)
        coordinator.beginDemoSession()

        do {
            _ = try await coordinator.saveTemplate(Data(), filename: "test.json")
            XCTFail("Expected SyncError.demoMode")
        } catch SyncError.demoMode {
            // Expected.
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_deleteTemplate_in_demo_throws_demoMode() async {
        let provider = FakeSyncProvider()
        let coordinator = SyncCoordinator(testingProvider: provider)
        coordinator.beginDemoSession()

        do {
            try await coordinator.deleteTemplate(at: "/some/path.json")
            XCTFail("Expected SyncError.demoMode")
        } catch SyncError.demoMode {
            // Expected.
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_downloadTemplate_in_demo_throws_demoMode() async {
        let provider = FakeSyncProvider()
        let coordinator = SyncCoordinator(testingProvider: provider)
        coordinator.beginDemoSession()

        do {
            _ = try await coordinator.downloadTemplate(at: "/some/path.json")
            XCTFail("Expected SyncError.demoMode")
        } catch SyncError.demoMode {
            // Expected.
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - CRUD forwarders pass-through when not in demo

    func test_uploadSigned_when_not_in_demo_forwards_to_provider() async throws {
        let provider = FakeSyncProvider()
        let coordinator = SyncCoordinator(testingProvider: provider)

        let result = try await coordinator.uploadSigned(Data("pdf".utf8), filename: "Form - Test [2026-01-01].pdf")

        XCTAssertEqual(provider.uploadSignedCalls.count, 1, "Coordinator forwards to provider")
        XCTAssertEqual(result.path, "/Signed/Form - Test [2026-01-01].pdf")
    }

    func test_saveTemplate_when_not_in_demo_forwards_to_provider() async throws {
        let provider = FakeSyncProvider()
        let coordinator = SyncCoordinator(testingProvider: provider)

        _ = try await coordinator.saveTemplate(Data("json".utf8), filename: "tpl.json")

        XCTAssertEqual(provider.saveTemplateCalls.count, 1)
        XCTAssertEqual(provider.stored.count, 1)
    }

    func test_deleteTemplate_when_not_in_demo_forwards_to_provider() async throws {
        let provider = FakeSyncProvider()
        // Pre-populate the store so deleteTemplate has something to drop.
        let identifier = try await FakeSyncProviderHelper.preloadOne(provider)
        let coordinator = SyncCoordinator(testingProvider: provider)

        try await coordinator.deleteTemplate(at: identifier)

        XCTAssertEqual(provider.deleteTemplateCalls, [identifier])
        XCTAssertEqual(provider.stored.count, 0)
    }
}

// MARK: - Local helpers

@MainActor
private enum FakeSyncProviderHelper {
    /// Loads one template into the fake's store and returns its identifier.
    /// Local to this file so test bodies stay readable and don't reach
    /// across into `FakeSyncProvider`'s mutating internals.
    static func preloadOne(_ provider: FakeSyncProvider) async throws -> String {
        try await provider.saveTemplate(Data("seed".utf8), filename: "seed.json")
    }
}
