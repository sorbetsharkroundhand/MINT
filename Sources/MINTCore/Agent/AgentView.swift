import SwiftUI

/// 읽기 전용 Writing Agent 사이드바. 도구 진행을 조용히 드러내되 원고 포커스를
/// 빼앗는 팝업이나 자동 편집은 만들지 않는다 (PLAN §14 M10, ADR-3·4).
struct AgentView: View {
    @ObservedObject var agent: AgentController
    let theme: MintTheme
    /// 사이드바 셸 안에서는 제품명이 이미 보이므로 상태 설명만 남긴다.
    var embedded = false

    @State private var draft = ""
    @State private var expandedTraceIDs: Set<UUID> = []
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if !embedded {
                        Text("Writing Agent")
                            .font(MintFonts.uiFont(12, .semibold))
                            .foregroundStyle(theme.inkC)
                    }
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
        HStack(alignment: .top, spacing: 7) {
            if message.role == .user { Spacer(minLength: 24) }
            if message.role == .assistant {
                AgentDotOrb(theme: theme, active: false)
                    .padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(message.text)
                    .font(MintFonts.uiFont(11))
                    .foregroundStyle(theme.inkC)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if message.role == .assistant, !message.toolTrace.isEmpty {
                    traceToggle(for: message)
                    if expandedTraceIDs.contains(message.id) {
                        traceDetails(message.toolTrace)
                    }
                }
            }
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

    private func traceToggle(
        for message: AgentController.TranscriptMessage
    ) -> some View {
        let isExpanded = expandedTraceIDs.contains(message.id)
        return Button {
            if isExpanded {
                expandedTraceIDs.remove(message.id)
            } else {
                expandedTraceIDs.insert(message.id)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.novelC)
                Text("작업 과정 · 도구 \(message.toolTrace.count)회")
                    .font(MintFonts.uiFont(9.5, .medium))
                    .foregroundStyle(theme.ink2C)
                Spacer(minLength: 5)
                GlassSwitch(isOn: isExpanded, theme: theme)
                    .scaleEffect(0.68)
                    .frame(width: 30, height: 18)
            }
            .padding(.top, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "작업 과정 접기" : "판단 요약과 사용한 도구 보기")
    }

    private func traceDetails(_ traces: [AgentToolTrace]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            theme.sepC.frame(height: 1)
            Text("비공개 사고 원문이 아니라 실제 도구 선택·입력·결과를 바탕으로 한 요약입니다.")
                .font(MintFonts.uiFont(8.5))
                .foregroundStyle(theme.ink3C)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(traces.enumerated()), id: \.offset) { _, trace in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text("\(trace.step)단계")
                            .font(MintFonts.uiFont(8.5, .semibold))
                            .foregroundStyle(theme.novelC)
                        Text(trace.toolName)
                            .font(MintFonts.uiFont(8.5, .medium))
                            .foregroundStyle(theme.ink2C)
                            .textSelection(.enabled)
                    }
                    traceLine(
                        title: "판단",
                        text: traceReason(for: trace.toolName, fallback: trace.label)
                    )
                    traceLine(
                        title: "입력",
                        text: AgentTraceFormatter.arguments(trace.arguments)
                    )
                    traceLine(title: "결과", text: trace.resultSummary)
                }
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(theme.pillC)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(theme.pillBorderC, lineWidth: 1)
                        )
                )
            }
        }
        .padding(.top, 6)
    }

    private func traceLine(title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text(title)
                .font(MintFonts.uiFont(8.5, .semibold))
                .foregroundStyle(theme.ink3C)
                .frame(width: 25, alignment: .leading)
            Text(text)
                .font(MintFonts.uiFont(8.5))
                .foregroundStyle(theme.ink2C)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var progressCard: some View {
        HStack(alignment: .top, spacing: 8) {
            AgentDotOrb(theme: theme, active: true)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(agent.activities) { activity in
                    HStack(alignment: .top, spacing: 6) {
                        Image(
                            systemName: activity.isFinished
                                ? "checkmark.circle.fill" : "circle.dotted"
                        )
                        .font(.system(size: 9.5))
                        .foregroundStyle(activity.isFinished ? theme.ink3C : theme.novelC)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.toolName)
                                .font(MintFonts.uiFont(9, .medium))
                                .foregroundStyle(theme.ink2C)
                            Text(activity.text)
                                .font(MintFonts.uiFont(9.5))
                                .foregroundStyle(theme.ink3C)
                                .fixedSize(horizontal: false, vertical: true)
                            if !activity.argumentsText.isEmpty {
                                Text(activity.argumentsText)
                                    .font(MintFonts.uiFont(8.5))
                                    .foregroundStyle(theme.ink3C)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if !agent.streamingText.isEmpty {
                    Text(agent.streamingText)
                        .font(MintFonts.uiFont(11))
                        .foregroundStyle(theme.ink2C)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else if agent.activities.isEmpty || agent.activities.last?.isFinished == true {
                    Text("작품을 살펴보는 중…")
                        .font(MintFonts.uiFont(10, .medium))
                        .foregroundStyle(theme.ink3C)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                .lineLimit(1 ... 4)
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

    private func traceReason(for toolName: String, fallback: String) -> String {
        switch toolName {
        case "get_active_document":
            "질문의 기준이 되는 활성 문서 정보를 먼저 확인했어요."
        case "get_outline":
            "관련 장면의 범위를 좁히기 위해 작품 전체 구조를 확인했어요."
        case "read_scene":
            "판단 근거를 요약이 아닌 실제 씬 원문에서 확인했어요."
        case "search_text":
            "요청한 표현이 등장하는 정확한 위치와 문맥을 찾았어요."
        case "find_character":
            "이름·별칭이 같은 인물을 혼동하지 않도록 등록 카드를 식별했어요."
        case "get_character_state":
            "답변 시점의 인물 상태를 추측하지 않고 준비된 지식에서 확인했어요."
        case "get_character_events":
            "인물에 대한 판단을 뒷받침하는 이전 사건을 확인했어요."
        case "get_character_dialogues":
            "인물의 말투와 대화 습관을 실제 이전 대사와 비교했어요."
        case "get_relation":
            "두 인물 사이의 방향 있는 관계와 존대 변화를 확인했어요."
        case "get_timeline":
            "사건의 등장 순서와 작품 안 시간순을 구분해 확인했어요."
        case "check_consistency":
            "결정적 규칙으로 잡을 수 있는 설정·말투 충돌을 검사했어요."
        case "get_context_at_cursor":
            "현재 서사 위치와 자동완성이 실제 참고할 지식을 확인했어요."
        default:
            fallback
        }
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

/// 매끈한 글래스 셸 안에서 Agent만의 존재감을 만드는 작은 도트 구체.
/// 생성 중에도 넓은 이동·회전은 쓰지 않고 표정과 1px 호흡만 바꿔 집필 집중을
/// 지킨다. 색은 현재 MintTheme를 그대로 받아 라이트·다크·사용자 팔레트에 맞는다.
private struct AgentDotOrb: View {
    let theme: MintTheme
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 0.34,
                paused: !active || reduceMotion
            )
        ) { timeline in
            let phase = active && !reduceMotion
                ? Int(timeline.date.timeIntervalSinceReferenceDate * 3) % 4
                : 0
            ZStack {
                Circle()
                    .fill(theme.novelBgC.opacity(0.72))
                    .overlay {
                        Circle().strokeBorder(theme.pillBorderC, lineWidth: 1)
                    }
                Canvas { context, size in
                    drawDots(in: &context, size: size)
                    drawFace(in: &context, size: size, phase: phase)
                }
                .padding(2)
            }
            .frame(width: 29, height: 29)
            .offset(y: active && !reduceMotion && phase == 1 ? -1 : 0)
            .shadow(color: theme.novelC.opacity(0.18), radius: 5, y: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(active ? "MINT Agent가 답변하는 중" : "MINT Agent")
    }

    /// 7×7 격자에서 원 안의 점만 남긴다. 좌상단은 밝고 우하단은 차분하게 해
    /// 작은 크기에서도 공의 부피가 읽히며, 픽셀 스프라이트 같은 인상을 만든다.
    private func drawDots(in context: inout GraphicsContext, size: CGSize) {
        let cell = size.width / 7
        let center = 3.0
        for row in 0 ..< 7 {
            for column in 0 ..< 7 {
                let dx = Double(column) - center
                let dy = Double(row) - center
                guard dx * dx + dy * dy <= 10.2 else { continue }
                let diameter = cell * 0.76
                let rect = CGRect(
                    x: (CGFloat(column) + 0.5) * cell - diameter / 2,
                    y: (CGFloat(row) + 0.5) * cell - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                let highlight = max(0, 1 - CGFloat(row + column) / 16)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(theme.novelC.opacity(0.64 + 0.30 * highlight))
                )
            }
        }
    }

    private func drawFace(
        in context: inout GraphicsContext, size: CGSize, phase: Int
    ) {
        let unit = size.width / 7
        let eyeY = size.height * 0.43
        for eyeX in [size.width * 0.36, size.width * 0.64] {
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: eyeX - unit * 0.30, y: eyeY - unit * 0.30,
                        width: unit * 0.60, height: unit * 0.60
                    )
                ),
                with: .color(theme.inkC.opacity(0.88))
            )
        }

        // 말하는 동안 한 점/세 점을 오가고, 멈추면 작은 미소로 남는다.
        let mouthPoints: [(CGFloat, CGFloat)] = if active && phase.isMultiple(of: 2) {
            [(0.50, 0.66)]
        } else {
            [(0.42, 0.64), (0.50, 0.68), (0.58, 0.64)]
        }
        for point in mouthPoints {
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: size.width * point.0 - unit * 0.24,
                        y: size.height * point.1 - unit * 0.24,
                        width: unit * 0.48, height: unit * 0.48
                    )
                ),
                with: .color(theme.inkC.opacity(0.82))
            )
        }
    }
}
