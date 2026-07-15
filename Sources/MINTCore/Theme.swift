import AppKit
import SwiftUI

/// 디자인 "MINT Editor v3"의 색·폰트 토큰.
///
/// 값은 목업의 CSS 변수(themeVars)를 그대로 옮긴 것 — 라이트/다크 두 벌.
/// 에디터(NSTextView)와 SwiftUI 크롬이 같은 팔레트를 공유한다.
public struct MintTheme: @unchecked Sendable {  // NSColor 불변 보관만 하므로 안전
    public let ink: NSColor
    public let ink2: NSColor
    public let ink3: NSColor
    public let ghost: NSColor
    public let blue: NSColor
    public let sep: NSColor
    public let sepStrong: NSColor
    public let hover: NSColor
    public let activeBg: NSColor
    public let chip: NSColor
    public let chipBorder: NSColor
    public let pill: NSColor
    public let pillBorder: NSColor
    public let kbd: NSColor
    public let codeBg: NSColor
    public let glassWin: NSColor
    public let toolbar: NSColor
    public let sidebarTint: NSColor
    public let statusbar: NSColor
    /// 커서가 놓인 줄의 은은한 하이라이트 (글로우 대체 — 에디터 v3.1).
    public let activeLine: NSColor
    /// 드래그 선택 영역 틴트 — 시스템 사각 하이라이트 대신 우리가 그리는
    /// 라운드 영역 표시의 채움색. 앱 이름 그대로 **민트** 계열 — 파랑(액센트)과
    /// 구분되는 MINT만의 선택 표시 (다크는 유리 배경 위에서 읽히도록 더 진하게).
    public let selection: NSColor
    /// 드래그 선택 영역의 헤어라인 테두리 — 채움과 같은 민트 계열, 더 또렷하게.
    public let selectionBorder: NSColor
    /// 소설 글쓰기 액센트 — 저널(파랑)과 나란히 놓아도 구분되는 보라 계열.
    public let novel: NSColor
    /// 소설 액센트의 은은한 배경 틴트 (활성 행·배지).
    public let novelBg: NSColor

    public static let light = MintTheme(
        ink: NSColor(hex: 0x1C1C1E),
        ink2: NSColor(hex: 0x6B6B70),
        ink3: NSColor(hex: 0x9A9A9F),
        ghost: NSColor(hex: 0xB4B4B9),
        blue: NSColor(hex: 0x0A84FF),
        sep: NSColor(white: 0, alpha: 0.08),
        sepStrong: NSColor(white: 0, alpha: 0.12),
        hover: NSColor(white: 0, alpha: 0.05),
        activeBg: NSColor(hex: 0x0A84FF, alpha: 0.10),
        chip: NSColor(white: 0, alpha: 0.05),
        chipBorder: NSColor(white: 0, alpha: 0.09),
        pill: NSColor(white: 1, alpha: 0.74),
        pillBorder: NSColor(white: 1, alpha: 0.85),
        kbd: NSColor.white,
        codeBg: NSColor(white: 0, alpha: 0.05),
        glassWin: NSColor(white: 1, alpha: 0.52),
        toolbar: NSColor(white: 1, alpha: 0.28),
        sidebarTint: NSColor(white: 0, alpha: 0.018),
        statusbar: NSColor(white: 1, alpha: 0.24),
        // 현재 줄 인식이 실제로 느껴지도록 아주 옅던 값을 살짝 올린다 (L3).
        activeLine: NSColor(white: 0, alpha: 0.055),
        selection: NSColor(hex: 0x00C7BE, alpha: 0.16),
        selectionBorder: NSColor(hex: 0x00A89E, alpha: 0.45),
        novel: NSColor(hex: 0xA550E0),
        novelBg: NSColor(hex: 0xA550E0, alpha: 0.10)
    )

    public static let dark = MintTheme(
        ink: NSColor(hex: 0xF2F2F0),
        ink2: NSColor(hex: 0x9A9A9F),
        ink3: NSColor(hex: 0x6E6E74),
        // 본문(0xF2F2F0)보다는 확실히 흐리되, 어두운 유리 배경 위에서 읽히는 밝기.
        ghost: NSColor(hex: 0x8E8E96),
        blue: NSColor(hex: 0x0A84FF),
        sep: NSColor(white: 1, alpha: 0.09),
        sepStrong: NSColor(white: 1, alpha: 0.16),
        hover: NSColor(white: 1, alpha: 0.06),
        activeBg: NSColor(hex: 0x0A84FF, alpha: 0.18),
        chip: NSColor(white: 1, alpha: 0.07),
        chipBorder: NSColor(white: 1, alpha: 0.12),
        pill: NSColor(red: 44 / 255, green: 44 / 255, blue: 48 / 255, alpha: 0.72),
        pillBorder: NSColor(white: 1, alpha: 0.14),
        kbd: NSColor(white: 1, alpha: 0.1),
        codeBg: NSColor(white: 1, alpha: 0.07),
        glassWin: NSColor(red: 20 / 255, green: 20 / 255, blue: 22 / 255, alpha: 0.55),
        toolbar: NSColor(white: 1, alpha: 0.04),
        sidebarTint: NSColor(white: 1, alpha: 0.028),
        statusbar: NSColor(white: 1, alpha: 0.03),
        // 어두운 유리 위에서 현재 줄이 또렷하도록 살짝 올린다 (L3).
        activeLine: NSColor(white: 1, alpha: 0.075),
        selection: NSColor(hex: 0x00C7BE, alpha: 0.26),
        selectionBorder: NSColor(hex: 0x4DE0D6, alpha: 0.55),
        novel: NSColor(hex: 0xBF5AF2),
        novelBg: NSColor(hex: 0xBF5AF2, alpha: 0.18)
    )

    public static func of(_ scheme: ColorScheme) -> MintTheme {
        scheme == .dark ? .dark : .light
    }

    // SwiftUI 크롬용 브리지.
    public var inkC: Color { Color(nsColor: ink) }
    public var ink2C: Color { Color(nsColor: ink2) }
    public var ink3C: Color { Color(nsColor: ink3) }
    public var ghostC: Color { Color(nsColor: ghost) }
    public var blueC: Color { Color(nsColor: blue) }
    public var sepC: Color { Color(nsColor: sep) }
    public var sepStrongC: Color { Color(nsColor: sepStrong) }
    public var hoverC: Color { Color(nsColor: hover) }
    public var activeBgC: Color { Color(nsColor: activeBg) }
    public var chipC: Color { Color(nsColor: chip) }
    public var chipBorderC: Color { Color(nsColor: chipBorder) }
    public var pillC: Color { Color(nsColor: pill) }
    public var pillBorderC: Color { Color(nsColor: pillBorder) }
    public var kbdC: Color { Color(nsColor: kbd) }
    public var glassWinC: Color { Color(nsColor: glassWin) }
    public var toolbarC: Color { Color(nsColor: toolbar) }
    public var sidebarTintC: Color { Color(nsColor: sidebarTint) }
    public var statusbarC: Color { Color(nsColor: statusbar) }
    public var novelC: Color { Color(nsColor: novel) }
    public var novelBgC: Color { Color(nsColor: novelBg) }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// 디자인 폰트 — Noto Serif KR(본문)·Pretendard(UI). 설치돼 있으면 쓰고,
/// 없으면 **한글을 덮는** 대체 폰트로 내려간다 (앱에 폰트를 번들하지 않는다).
///
/// ⚠️ 폴백은 취향 문제가 아니라 **성능 문제**다 (2026-07-15 측정, docs/editor-perf.md).
/// 한글을 못 덮는 폰트(시스템 serif = New York)를 본문에 깔면 NSTextStorage의
/// 폰트 고정이 한글마다 대체 런을 쪼갠다 — 88k자 원고에서 속성 런이 537개 →
/// **42,678개**로 폭발하고, 매 키 입력마다 도는 `serialize()`가 5ms → **43ms**가
/// 되어 프레임을 놓친다. 한국어 앱에서 라틴 전용 폰트 폴백은 금지다.
public enum MintFonts {
    /// 설치된 본문 세리프 패밀리. 전부 **한글 커버 필수** — 앞에서부터 고른다.
    /// Nanum Myeongjo·AppleMyungjo는 macOS 한국어 지원에 딸려 오는 명조체다
    /// (Nanum은 Bold 보유, AppleMyungjo는 Regular뿐이라 뒤에 둔다).
    static let serifFamily: String? = [
        "Noto Serif KR", "NotoSerifKR", "Nanum Myeongjo", "AppleMyungjo",
    ]
    .first { NSFontManager.shared.availableFontFamilies.contains($0) }

    /// UI 산세리프. Apple SD Gothic Neo는 한글 9종 굵기로 macOS에 항상 있다.
    static let uiFamily: String? = [
        "Pretendard Variable", "Pretendard", "Apple SD Gothic Neo",
    ]
    .first { NSFontManager.shared.availableFontFamilies.contains($0) }

    /// 본문 세리프 (AppKit).
    public static func serif(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let family = serifFamily,
            let font = NSFontManager.shared.font(
                withFamily: family, traits: [], weight: Self.fontManagerWeight(weight),
                size: size)
        {
            return font
        }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// UI 산세리프 (AppKit).
    public static func ui(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let family = uiFamily,
            let font = NSFontManager.shared.font(
                withFamily: family, traits: [], weight: Self.fontManagerWeight(weight),
                size: size)
        {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// 본문 세리프 (SwiftUI).
    public static func serifUI(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let family = serifFamily {
            return Font.custom(family, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    /// UI 산세리프 (SwiftUI).
    public static func uiFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let family = uiFamily {
            return Font.custom(family, size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }

    /// 모노 (상태·칩·kbd).
    public static func monoUI(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// NSFontManager 가중치(0-15)로 변환.
    private static func fontManagerWeight(_ weight: NSFont.Weight) -> Int {
        switch weight {
        case .ultraLight: 1
        case .thin: 2
        case .light: 3
        case .regular: 5
        case .medium: 6
        case .semibold: 8
        case .bold: 9
        case .heavy: 10
        case .black: 11
        default: 5
        }
    }
}
