import AppKit
import SwiftUI

/// Onboarding actions stay on the verified ProjectSession/ProjectStore coordinator path.
@MainActor
public struct FirstRunFlow {
    private let creationCoordinator: ProjectCreationCoordinator
    private let importCoordinator: ImportProjectCoordinator
    private let editorRequests: ProjectEditorRequests

    public init(
        session: ProjectSession,
        store: ProjectStore,
        editorRequests: ProjectEditorRequests
    ) {
        self.creationCoordinator = ProjectCreationCoordinator(session: session)
        self.importCoordinator = ImportProjectCoordinator(store: store, session: session)
        self.editorRequests = editorRequests
    }

    public func createProject(mode: WritingMode) async throws {
        try await creationCoordinator.createProject(title: "", mode: mode)
        editorRequests.focusEditor()
    }

    func importFolder(selection: ProjectFolderSelection?) async throws {
        // NSOpenPanel cancellation ends here, before migration or activation begins.
        guard let selection else { return }
        try await importCoordinator.importFolder(
            from: selection.directory, legacyMode: selection.legacyMode)
        editorRequests.focusEditor()
    }
}

/// First launch asks only what the writer wants to open; model setup remains in Settings.
public struct FirstRunView: View {
    private enum Operation: Equatable {
        case fiction
        case general
        case folderImport
    }

    private let flow: FirstRunFlow
    @Environment(\.colorScheme) private var colorScheme
    @State private var operation: Operation?
    @State private var errorMessage: String?

    public init(flow: FirstRunFlow) {
        self.flow = flow
    }

    public var body: some View {
        let theme = MintTheme.of(colorScheme)
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 7) {
                Text("MINT")
                    .mintSerifFont(32, .semibold)
                    .foregroundStyle(theme.inkC)
                Text("무엇을 쓰든, 먼저 원고부터 여세요.")
                    .mintUIFont(14)
                    .foregroundStyle(theme.ink2C)
            }

            VStack(spacing: 10) {
                projectButton(
                    title: "Fiction 시작",
                    detail: "장면과 인물을 위한 소설 작업 공간",
                    symbol: "book.closed",
                    operation: .fiction,
                    theme: theme
                ) {
                    try await flow.createProject(mode: .fiction)
                }
                projectButton(
                    title: "General Writing 시작",
                    detail: "에세이, 메모, 그 밖의 모든 글",
                    symbol: "doc.text",
                    operation: .general,
                    theme: theme
                ) {
                    try await flow.createProject(mode: .general)
                }

                Button {
                    guard let selection = ProjectImportPanel.select() else { return }
                    perform(.folderImport) {
                        try await flow.importFolder(selection: selection)
                    }
                } label: {
                    Label("기존 MINT 원고 가져오기…", systemImage: "square.and.arrow.down")
                        .mintUIFont(12, .medium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(operation != nil)
                .accessibilityIdentifier("mint.first-run.import")
            }

            if let errorMessage {
                Text(errorMessage)
                    .mintUIFont(12)
                    .foregroundStyle(theme.dangerC)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("프로젝트 열기 오류: \(errorMessage)")
            }

            Text("AI 자동완성은 선택 사항이며 설정에서 직접 켤 때까지 모델을 내려받지 않습니다.")
                .mintUIFont(11)
                .foregroundStyle(theme.ink3C)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(44)
        .frame(width: 500)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.editorSurfaceC)
    }

    private func projectButton(
        title: String,
        detail: String,
        symbol: String,
        operation requestedOperation: Operation,
        theme: MintTheme,
        action: @escaping @MainActor () async throws -> Void
    ) -> some View {
        Button {
            perform(requestedOperation, action: action)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.novelC)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .mintUIFont(14, .semibold)
                        .foregroundStyle(theme.inkC)
                    Text(detail)
                        .mintUIFont(11)
                        .foregroundStyle(theme.ink2C)
                }
                Spacer()
                if operation == requestedOperation {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.ink3C)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: MintRadius.md, style: .continuous)
                    .fill(theme.chipC)
                    .overlay(
                        RoundedRectangle(cornerRadius: MintRadius.md, style: .continuous)
                            .stroke(theme.chipBorderC, lineWidth: 1)))
            .contentShape(RoundedRectangle(cornerRadius: MintRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(operation != nil)
        .accessibilityIdentifier(
            requestedOperation == .fiction ? "mint.first-run.fiction" : "mint.first-run.general")
    }

    private func perform(
        _ requestedOperation: Operation,
        action: @escaping @MainActor () async throws -> Void
    ) {
        guard operation == nil else { return }
        operation = requestedOperation
        errorMessage = nil
        Task { @MainActor in
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
            operation = nil
        }
    }

}
