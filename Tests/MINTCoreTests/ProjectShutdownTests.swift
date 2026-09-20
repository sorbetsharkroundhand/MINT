import AppKit
import XCTest
@testable import MINTCore

@MainActor
final class ProjectShutdownTests: XCTestCase {
    // Catches shutting resources down or replying before the last accepted project edit is durable.
    func testSuccessfulTerminationFlushesProjectBeforePositionsShutdownAndDrain() async throws {
        let fixture = try await LegacyBoundaryFixture()
        defer { fixture.cleanUp() }
        fixture.session.updateSelectedDocumentBody("last accepted sentence")
        var events: [String] = []
        let coordinator = ProjectTerminationCoordinator(
            session: fixture.session, legacyWorkspace: fixture.controller(),
            persistPositions: { events.append("positions") },
            shutdown: { events.append("shutdown") },
            drain: {
                events.append("drain")
                let durable = try? await fixture.store.activeProject()
                XCTAssertEqual(durable?.documents[0].body, "last accepted sentence")
            })
        let result = await coordinator.prepareForTermination()
        XCTAssertEqual(result, .terminateNow)
        XCTAssertEqual(events, ["positions", "shutdown", "drain"])
        XCTAssertEqual(fixture.session.savePhase, .saved)
        fixture.session.updateSelectedDocumentBody("too late after shutdown")
        XCTAssertEqual(fixture.session.selectedDocument?.body, "last accepted sentence")
    }

    // Catches false success or irreversible shutdown after a project save failure.
    func testProjectSaveFailureCancelsTerminationAndKeepsEditableDirtyOwner() async throws {
        let fixture = try await LegacyBoundaryFixture(failProjectWrites: true)
        defer { fixture.cleanUp() }
        fixture.session.updateSelectedDocumentBody("unsaved latest sentence")
        var shutdown = false
        var drained = false
        let coordinator = ProjectTerminationCoordinator(
            session: fixture.session, legacyWorkspace: fixture.controller(),
            persistPositions: {}, shutdown: { shutdown = true }, drain: { drained = true })
        let result = await coordinator.prepareForTermination()
        XCTAssertEqual(result, .terminateCancel)
        XCTAssertFalse(shutdown)
        XCTAssertFalse(drained)
        XCTAssertEqual(fixture.session.savePhase, .failed)
        XCTAssertEqual(fixture.session.selectedDocument?.body, "unsaved latest sentence")
        XCTAssertNotNil(fixture.session.lastErrorMessage)
        fixture.session.updateSelectedDocumentBody("still editable")
        XCTAssertEqual(fixture.session.selectedDocument?.body, "still editable")
        let durable = try await fixture.store.activeProject()
        XCTAssertEqual(durable?.documents[0].body, "original project")
    }

    // Catches accidentally flushing the suspended project or EntryStore.current instead of its owner.
    func testLegacyTerminationFlushesActiveLegacyBeforeShutdown() async throws {
        let fixture = try await LegacyBoundaryFixture()
        defer { fixture.cleanUp() }
        let legacy = fixture.controller()
        try await legacy.enter()
        legacy.legacyStore?.updateActiveBody("legacy last sentence")
        EntryStore.current = nil
        let coordinator = ProjectTerminationCoordinator(
            session: fixture.session, legacyWorkspace: legacy,
            persistPositions: {}, shutdown: {}, drain: {})
        let result = await coordinator.prepareForTermination()
        XCTAssertEqual(result, .terminateNow)
        legacy.updateLegacyBody("too late after legacy shutdown")
        XCTAssertEqual(legacy.legacyStore?.activeEntry?.body, "legacy last sentence")
        let data = try Data(contentsOf: fixture.legacyRoot.appendingPathComponent("entries.json"))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("legacy last sentence"))
        XCTAssertNil(fixture.session.activeProject)
        let durable = try await fixture.store.activeProject()
        XCTAssertEqual(durable?.documents[0].body, "original project")
    }

    // Catches losing the only legacy edits on failure and prevents duplicate cancellation replies.
    func testLegacyFailureRepliesFalseOnceAndAllowsRetry() async throws {
        let fixture = try await LegacyBoundaryFixture()
        defer { fixture.cleanUp() }
        let legacy = fixture.controller()
        try await legacy.enter()
        let owner = try XCTUnwrap(legacy.legacyStore)
        owner.updateActiveBody("retain legacy edits")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.legacyRoot.path)
        var shutdowns = 0
        let coordinator = ProjectTerminationCoordinator(
            session: fixture.session, legacyWorkspace: legacy,
            persistPositions: {}, shutdown: { shutdowns += 1 }, drain: {})
        let cancelled = expectation(description: "Save failure cancels quit")
        var replies: [Bool] = []
        XCTAssertEqual(coordinator.requestTermination { replies.append($0); cancelled.fulfill() }, .terminateLater)
        XCTAssertEqual(coordinator.requestTermination { _ in XCTFail("Duplicate termination reply") }, .terminateLater)
        await fulfillment(of: [cancelled], timeout: 3)
        XCTAssertEqual(replies, [false])
        XCTAssertEqual(shutdowns, 0)
        XCTAssertTrue(owner === legacy.legacyStore)
        XCTAssertEqual(owner.activeEntry?.body, "retain legacy edits")
        XCTAssertEqual(legacy.mode, .legacy)
        XCTAssertFalse(legacy.isTransitioning)
        XCTAssertNotNil(fixture.session.lastErrorMessage)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.legacyRoot.path)
        let retried = expectation(description: "Retry succeeds")
        XCTAssertEqual(coordinator.requestTermination { replies.append($0); retried.fulfill() }, .terminateLater)
        await fulfillment(of: [retried], timeout: 3)
        XCTAssertEqual(replies, [false, true])
        XCTAssertEqual(shutdowns, 1)
    }

    // Catches launching a second save/shutdown task while AppKit waits for the engine to drain.
    func testRepeatedTerminationRequestsShareOneTaskAndOneReply() async throws {
        let fixture = try await LegacyBoundaryFixture()
        defer { fixture.cleanUp() }
        fixture.session.updateSelectedDocumentBody("durable once")
        let started = expectation(description: "Drain starts")
        let replied = expectation(description: "AppKit reply")
        let gate = AsyncStream<Void>.makeStream()
        var shutdowns = 0
        var replies = 0
        let coordinator = ProjectTerminationCoordinator(
            session: fixture.session, legacyWorkspace: fixture.controller(),
            persistPositions: {}, shutdown: { shutdowns += 1 }, drain: {
                started.fulfill()
                for await _ in gate.stream { break }
            })
        XCTAssertEqual(coordinator.requestTermination { success in
            XCTAssertTrue(success); replies += 1; replied.fulfill()
        }, .terminateLater)
        await fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(replies, 0)
        XCTAssertEqual(coordinator.requestTermination { _ in XCTFail("Duplicate reply") }, .terminateLater)
        gate.continuation.yield(())
        gate.continuation.finish()
        await fulfillment(of: [replied], timeout: 3)
        XCTAssertEqual(shutdowns, 1)
        XCTAssertEqual(replies, 1)
        XCTAssertEqual(coordinator.requestTermination { _ in XCTFail("Reply after approved termination") }, .terminateLater)
    }
}
