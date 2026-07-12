import SwiftUI

/// 수식 소스 편집 중 문단 아래에 뜨는 라이브 미리보기 (수식 블럭 완성도).
///
/// 타이핑할 때마다 렌더 결과를 즉시 보여줘, 커서를 밖으로 빼기 전에도
/// 수식이 의도대로 그려지는지 알 수 있다. 파싱이 안 되면 오류 안내를,
/// 아직 비어 있으면 입력 힌트를 보여준다.
struct MathPreviewView: View {
    let theme: MintTheme
    /// 렌더 성공 결과 — nil이면 message를 보여준다.
    let image: NSImage?
    /// 빈 수식 힌트·파싱 오류 안내 (image가 nil일 때).
    let message: String?
    /// 오류(파싱 실패)인지 — 힌트보다 또렷한 잉크로 구분한다.
    let isError: Bool

    /// 미리보기 이미지의 최대 표시 폭 — 본문 컬럼을 넘지 않게 축소한다.
    private static let maxImageWidth: CGFloat = 520

    var body: some View {
        Group {
            if let image {
                let scale = min(1, Self.maxImageWidth / max(image.size.width, 1))
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: image.size.width * scale,
                        height: image.size.height * scale)
            } else if let message {
                Text(message)
                    .font(MintFonts.uiFont(11.5))
                    .foregroundStyle(isError ? theme.ink2C : theme.ink3C)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.pillC)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.pillBorderC)
        )
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
    }
}
