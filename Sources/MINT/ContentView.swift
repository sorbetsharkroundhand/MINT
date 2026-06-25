import SwiftUI

/// M0 단계의 임시 에디터 화면.
///
/// 지금은 순수 SwiftUI `TextEditor`로 "타이핑되는 창"만 보여준다.
/// M1에서 이 자리를 커스텀 `NSTextView` 래퍼(`MintTextView`)로 교체해
/// 인라인 고스트 텍스트 자동완성과 `.md` 자동 저장을 지원할 예정이다.
struct ContentView: View {
    @State private var text: String = ""

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 16, design: .serif))
            .lineSpacing(4)
            .scrollContentBackground(.hidden)
            .padding(28)
            .frame(minWidth: 480, minHeight: 360)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("오늘을 기록해보세요…")
                        .font(.system(size: 16, design: .serif))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 36)
                        .padding(.leading, 33)
                        .allowsHitTesting(false)
                }
            }
    }
}

#Preview {
    ContentView()
}
