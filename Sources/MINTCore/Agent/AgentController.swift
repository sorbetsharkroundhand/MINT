import Foundation
import SwiftUI

@MainActor
public final class AgentController: ObservableObject {
    public struct TranscriptMessage: Identifiable, Sendable, Equatable {
        public enum Role: Sendable { case user, assistant }
        public let id: UUID
        public var role: Role
        public var text: String

        public init(id: UUID = UUID(), role: Role, text: String) {
            self.id = id
            self.role = role
            self.text = text
        }
    }

    public struct Activity: Identifiable, Sendable, Equatable {
        public let id: UUID
        public var toolName: String
        public var text: String
        public var isFinished: Bool

        public init(
            id: UUID = UUID(), toolName: String,
            text: String, isFinished: Bool = false
        ) {
            self.id = id
            self.toolName = toolName
            self.text = text
            self.isFinished = isFinished
        }
    }

    @Published public private(set) var messages: [TranscriptMessage] = []
    @Published public private(set) var activities: [Activity] = []
    @Published public private(set) var streamingText = ""
    @Published public private(set) var isRunning = false
    @Published public private(set) var lastError: String?

    /// ContentView가 값 스냅샷 공급자로 배선한다. Agent는 Store/Indexer 객체를
    /// 직접 잡지 않는다.
    public var sourceProvider: (() -> AgentSourceSnapshot?)?
    public var parametersProvider: (() -> CompletionParameters)?
    /// 고스트·백그라운드 이해와 단일 모델 선점을 조율하는 배선.
    public var runningDidChange: ((Bool) -> Void)?

    private let runtime: AgentRuntime
    private var task: Task<Void, Never>?

    public init(engine: CompletionEngine) {
        runtime = AgentRuntime(generator: engine)
    }

    public init(runtime: AgentRuntime) {
        self.runtime = runtime
    }

    public func send(_ raw: String) {
        let request = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isRunning else { return }
        guard let source = sourceProvider?() else {
            lastError = "열린 문서가 없어 Agent가 읽을 수 없어요."
            return
        }

        let prior = messages.map { message in
            AgentChatMessage(
                role: message.role == .user ? .user : .assistant,
                content: message.text)
        }
        var parameters = parametersProvider?() ?? CompletionSettings.shared.parameters
        parameters.maxTokens = 512
        parameters.temperature = min(0.4, max(0.1, parameters.temperature))
        parameters.stopAtUtteranceEnd = false

        messages.append(TranscriptMessage(role: .user, text: request))
        activities = []
        streamingText = ""
        lastError = nil
        setRunning(true)

        task = Task { [weak self, runtime] in
            guard let self else { return }
            do {
                let result = try await runtime.run(
                    request: request, history: prior, source: source,
                    parameters: parameters,
                    onEvent: { event in
                        Task { @MainActor [weak self] in self?.consume(event) }
                    })
                guard !Task.isCancelled else { return }
                self.streamingText = ""
                self.messages.append(
                    TranscriptMessage(role: .assistant, text: result.text))
                self.setRunning(false)
            } catch is CancellationError {
                self.streamingText = ""
                self.setRunning(false)
            } catch {
                self.streamingText = ""
                self.lastError = error.localizedDescription
                self.messages.append(
                    TranscriptMessage(
                        role: .assistant,
                        text: "요청을 마치지 못했어요: \(error.localizedDescription)"))
                self.setRunning(false)
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        streamingText = ""
        setRunning(false)
    }

    public func clear() {
        guard !isRunning else { return }
        messages = []
        activities = []
        streamingText = ""
        lastError = nil
    }

    private func setRunning(_ value: Bool) {
        guard isRunning != value else { return }
        isRunning = value
        if !value { task = nil }
        runningDidChange?(value)
    }

    private func consume(_ event: AgentRuntimeEvent) {
        guard isRunning else { return }
        switch event {
        case .stepStarted:
            // 도구를 고르는 중간 출력은 다음 턴의 최종 답변과 섞지 않는다.
            streamingText = ""
        case .textChunk(let chunk):
            streamingText += chunk
        case .toolStarted(let name, let label):
            streamingText = ""
            activities.append(Activity(toolName: name, text: label))
        case .toolFinished(let name, let summary):
            if let index = activities.lastIndex(where: {
                $0.toolName == name && !$0.isFinished
            }) {
                activities[index].text = summary
                activities[index].isFinished = true
            } else {
                activities.append(
                    Activity(toolName: name, text: summary, isFinished: true))
            }
        case .repairingToolCall:
            activities.append(
                Activity(
                    toolName: "repair", text: "도구 호출 형식을 한 번 바로잡는 중…"))
        }
    }
}
