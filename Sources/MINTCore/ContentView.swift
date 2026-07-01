import SwiftUI

/// MINT의 단일 에디터 화면(M1).
///
/// 커스텀 `MintTextView`(NSTextView 래퍼)로 본문을 편집하고,
/// `DocumentStore`가 `~/Documents/MINT/journal.md`에 디바운스 autosave/load 한다.
/// M3에서 `MintTextView`에 인라인 고스트 텍스트 자동완성이 얹힌다.
public struct ContentView: View {
    @StateObject private var store = DocumentStore()

    public init() {}

    public var body: some View {
        MintTextView(text: $store.text)
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
            .onAppear { store.load() }
            .onChange(of: store.text) { _, _ in store.scheduleSave() }
    }
}

#Preview {
    ContentView()
}
