import SwiftUI

/// 읽기 전용 Writing Agent 사이드바. 도구 진행을 조용히 드러내되 원고 포커스를
/// 빼앗는 팝업이나 자동 편집은 만들지 않는다 (PLAN §14 M10, ADR-3·4).
struct AgentView: View {
    @ObservedObject var agent: AgentController
    let theme: MintTheme

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Writing Agent")
                        .font(MintFonts.uiFont(12, .semibold))
                        .foregroundStyle(theme.inkC)
                    Text("읽기 전용 · 원고를 직접 바꾸지 않아요")
                        .font(MintFonts.uiFont(9.5))
                        .foregroundStyle(theme.ink3C)
                }
                Spacer(minLength: 4)
                if agent.isRunning {
                    Button("중단") { agent.cancel() }
                        .buttonStyle(.plain)
                        .font(MintFonts.uiFont(10, .medium))
                        .foregroundStyle(theme.novelC)
                } else if !agent.messages.isEmpty {
                    Button { agent.clear() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.ink3C)
                    }
                    .buttonStyle(.plain)
                    .help("대화 지우기")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            theme.sepC.frame(height: 1)

            transcript

            theme.sepC.frame(height: 1)
            composer
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if agent.messages.isEmpty, !agent.isRunning {
                        emptyHint
                    }
                    ForEach(agent.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                    if agent.isRunning {
                        progressCard.id("agent-progress")
                    }
                }
                .padding(12)
            }
            .onChange(of: agent.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: agent.activities.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: agent.streamingText) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("작품에 관해 물어보세요")
                .font(MintFonts.uiFont(12, .medium))
                .foregroundStyle(theme.ink2C)
            Text("인물 상태·사건·관계·대사·시간순을 준비된 Story Intelligence와 원문에서 확인해 답해요.")
                .font(MintFonts.uiFont(10.5))
                .foregroundStyle(theme.ink3C)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                suggestion("지금 미해결 플롯이 뭐야?")
                suggestion("이 인물의 말투가 앞과 맞아?")
                suggestion("커서까지 일관성 문제를 찾아줘")
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.chipC)
        )
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            draft = text
            submit()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8.5))
                Text(text)
                    .font(MintFonts.uiFont(10))
                    .lineLimit(1)
            }
            .foregroundStyle(theme.ink2C)
        }
        .buttonStyle(.plain)
    }

    private func messageRow(_ message: AgentController.TranscriptMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 24) }
            Text(message.text)
                .font(MintFonts.uiFont(11))
                .foregroundStyle(theme.inkC)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(message.role == .user ? theme.novelBgC : theme.chipC)
                )
            if message.role == .assistant { Spacer(minLength: 12) }
        }
        .frame(maxWidth: .infinity)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(agent.activities) { activity in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: activity.isFinished ? "checkmark.circle.fill" : "circle.dotted")
                        .font(.system(size: 9.5))
                        .foregroundStyle(activity.isFinished ? theme.ink3C : theme.novelC)
                    Text(activity.text)
                        .font(MintFonts.uiFont(9.5))
                        .foregroundStyle(theme.ink3C)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !agent.streamingText.isEmpty {
                Text(agent.streamingText)
                    .font(MintFonts.uiFont(11))
                    .foregroundStyle(theme.ink2C)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if agent.activities.isEmpty || agent.activities.last?.isFinished == true {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("작품을 살펴보는 중…")
                        .font(MintFonts.uiFont(10))
                        .foregroundStyle(theme.ink3C)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.chipC)
        )
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 7) {
            TextField("작품에 관해 묻기", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(MintFonts.uiFont(11))
                .foregroundStyle(theme.inkC)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(submit)
                .disabled(agent.isRunning)
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(canSubmit ? theme.novelC : theme.ink3C)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .help("보내기")
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.pillC)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(theme.pillBorderC, lineWidth: 1)
                )
        )
        .padding(10)
    }

    private var canSubmit: Bool {
        !agent.isRunning && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        let request = draft
        draft = ""
        agent.send(request)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.16)) {
            if agent.isRunning {
                proxy.scrollTo("agent-progress", anchor: .bottom)
            } else if let last = agent.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
