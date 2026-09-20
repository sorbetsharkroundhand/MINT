import Combine
import Foundation

/// Explicit compatibility boundary: only one workspace may own editable manuscript state.
@MainActor
public final class LegacyWorkspaceController: ObservableObject {
    public enum Mode: Equatable { case project, legacy }

    @Published public private(set) var mode: Mode = .project
    @Published public private(set) var legacyStore: EntryStore?
    @Published public private(set) var isTransitioning = false
    @Published public private(set) var lastErrorMessage: String?
    public var didEnterLegacy: ((EntryStore) -> Void)?
    public var willFlushLegacy: (() -> Void)?
    public var willLeaveLegacy: (() -> Void)?

    private let session: ProjectSession
    private let entryStoreFactory: () -> EntryStore
    private var isFlushing = false

    public init(session: ProjectSession, entryStoreFactory: @escaping () -> EntryStore = { EntryStore() }) {
        self.session = session
        self.entryStoreFactory = entryStoreFactory
    }

    public func enter() async throws {
        guard !isTransitioning, !isFlushing else { throw ProjectSessionError.transitionInProgress }
        guard mode != .legacy else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        do {
            try await session.suspend(canResume: { [weak self] in self?.legacyStore == nil })
            let store = entryStoreFactory()
            legacyStore = store
            mode = .legacy
            lastErrorMessage = nil
            didEnterLegacy?(store)
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    public func updateLegacyBody(_ body: String) {
        guard mode == .legacy, !isTransitioning else { return }
        legacyStore?.updateActiveBody(body)
    }

    public func leave() async throws {
        guard !isTransitioning, !isFlushing else { throw ProjectSessionError.transitionInProgress }
        guard mode == .legacy || session.phase == .suspended else { return }
        willFlushLegacy?()
        isTransitioning = true
        defer { isTransitioning = false }
        do {
            try await flushLegacy()
            willLeaveLegacy?()
            legacyStore = nil
            mode = .project
            try await session.resume()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    /// Background/save commands resolve only the current explicit owner. The gate prevents
    /// a concurrent workspace handoff while an asynchronous save is still running.
    public func flushActiveOwner() async throws {
        guard !isTransitioning, !isFlushing else { throw ProjectSessionError.transitionInProgress }
        if mode == .legacy { willFlushLegacy?() }
        isFlushing = true
        defer { isFlushing = false }
        do {
            if mode == .legacy { try await flushLegacy() }
            else { try await session.flush() }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            session.reportError(error)
            throw error
        }
    }

    func flushForTermination() async throws {
        guard !isTransitioning, !isFlushing, session.phase != .loading else {
            throw ProjectSessionError.transitionInProgress
        }
        if mode == .legacy { willFlushLegacy?() }
        isTransitioning = true
        do {
            if mode == .legacy { try await flushLegacy() }
            else if session.phase != .suspended { try await session.flushForTermination() }
            lastErrorMessage = nil
        } catch {
            isTransitioning = false
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func flushLegacy() async throws {
        guard let legacyStore else { return }
        if let message = await legacyStore.flushAsync() {
            throw LegacyWorkspaceError.saveFailed(message)
        }
    }
}

public enum LegacyWorkspaceError: LocalizedError {
    case saveFailed(String)
    public var errorDescription: String? {
        switch self { case .saveFailed(let message): message }
    }
}
