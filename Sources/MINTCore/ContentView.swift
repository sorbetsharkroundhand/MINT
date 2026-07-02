import SwiftUI

/// MINT의 단일 에디터 화면 (M1 편집·저장 + M3 고스트 자동완성).
///
/// 커스텀 `MintTextView`(NSTextView 래퍼)로 본문을 편집하고,
/// `DocumentStore`가 `~/Documents/MINT/journal.md`에 디바운스 autosave/load 한다.
/// `CompletionController`가 입력 멈춤을 감지해 회색 고스트 제안을 띄운다 —
/// 고스트는 text storage 밖에 그려지므로 저장 파일에는 절대 섞이지 않는다.
public struct ContentView: View {
    @StateObject private var store = DocumentStore()
    @StateObject private var completion = CompletionController()

    public init() {}

    public var body: some View {
        MintTextView(text: $store.text, controller: completion)
            .frame(minWidth: 480, minHeight: 360)
            .overlay(alignment: .topLeading) {
                if store.text.isEmpty {
                    Text("오늘을 기록해보세요…")
                        .font(.system(size: 16, design: .serif))
                        .foregroundStyle(.tertiary)
                        // MintTextView의 textContainerInset(20,24)에 맞춰 정렬.
                        .padding(.top, 28)
                        .padding(.leading, 25)
                        .allowsHitTesting(false)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                EngineStatusBar(controller: completion)
            }
            .onAppear {
                store.load()
                // 모델 상주(PLAN §9-2) — 미리 로드해 첫 제안 지연(<~500ms)을 지킨다.
                completion.preloadEngine()
            }
            .onChange(of: store.text) { _, _ in store.scheduleSave() }
    }
}

/// 모델 준비 상태 + 최근 제안 지연을 보여주는 하단 상태 바 (M4 다듬기).
struct EngineStatusBar: View {
    @ObservedObject var controller: CompletionController

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)
            Text(stateText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if case .failed = controller.engineState {
                Button("다시 시도") { controller.retryEngineLoad() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Spacer()
            if let latency = controller.lastLatency {
                Text(String(format: "최근 제안 %.2fs", latency))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private var stateText: String {
        switch controller.engineState {
        case .idle:
            "자동완성 대기"
        case .downloading(let fraction):
            String(format: "모델 다운로드 %.0f%% — 첫 실행은 수 GB를 받아요", fraction * 100)
        case .loading:
            "모델 로드 중…"
        case .ready:
            "자동완성 준비됨 · 입력을 멈추면 회색 제안 · Tab 수락 / Esc 거부"
        case .failed(let message):
            "모델 로드 실패: \(message)"
        }
    }

    private var stateColor: Color {
        switch controller.engineState {
        case .idle: .gray
        case .downloading, .loading: .orange
        case .ready: .green
        case .failed: .red
        }
    }
}

#Preview {
    ContentView()
}
