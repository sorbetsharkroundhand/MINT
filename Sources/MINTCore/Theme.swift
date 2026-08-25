import AppKit
import SwiftUI

/// 디자인 "MINT Editor v3"의 색·폰트 토큰.
///
/// 값은 목업의 CSS 변수(themeVars)를 그대로 옮긴 것 — 라이트/다크 두 벌.
/// 에디터(NSTextView)와 SwiftUI 크롬이 같은 팔레트를 공유한다.
public struct MintTheme: Equatable, @unchecked Sendable {  // NSColor 불변 보관만 하므로 안전
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
    /// 위험(삭제·오류·파괴적 동작) 상태색 (#56) — 라이트는 흰 바탕 대비를 위해
    /// 진하게, 다크는 시스템 레드 계열.
    public let danger: NSColor
    /// 위험 배경 틴트 — 삭제 확인 배지·호버 면.
    public let dangerBg: NSColor
    /// 주의(다운로드 중·로딩 등 진행 경고) 상태색 (#56) — 상태 점·배지.
    public let warning: NSColor
    /// 토글 스위치 노브(GlassSwitch) — 유리 위에서도 읽히는 불투명 밝은 원.
    /// 그림자는 정의상 항상 검정 알파라 토큰으로 만들지 않는다 (예외, #56).
    public let knob: NSColor

    /// 소설 액센트 원색 — 기본 팔레트의 대표색과 같은 연둣빛.
    ///
    /// 다크 모드에선 이 색 그대로 쓴다(어두운 배경 대비 ~16:1). 라이트 모드는
    /// 흰 배경 대비가 1.16:1이라 그대로 두면 아이콘·강조 글자가 사라지므로,
    /// **색상은 지키고 명도만 낮춰** 파생한다 (`adjustedForContrast`).
    public static let accentSeed: UInt32 = 0xE9FF7A

    /// 라이트 모드용으로 어둡게 내린 액센트 — 연둣빛을 유지한 올리브.
    static let accentLight = NSColor(hex: accentSeed)
        .adjustedForContrast(against: .white, target: 4.5, darken: true)

    public static let light = MintTheme(
        ink: NSColor(hex: 0x1C1C1E),
        ink2: NSColor(hex: 0x6B6B70),
        // 4.5:1 (흰 배경) — 작은 의미 텍스트의 WCAG AA 최소치 (#29).
        // 과거 0x9A9A9F는 2.8:1로 캡션·힌트가 읽히지 않았다.
        ink3: NSColor(hex: 0x76767B),
        // ghost는 **장식 전용**(플레이스홀더·비의미 틴트) — 의미 텍스트에 쓰지
        // 않는다는 것이 토큰 계약이다 (#29). 대비 하한은 적용하지 않는다.
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
        novel: accentLight,
        // 배경 틴트는 원색 그대로 — 옅게 깔리는 면이라 대비 문제가 없다.
        novelBg: NSColor(hex: accentSeed, alpha: 0.28),
        danger: NSColor(hex: 0xD93025),
        dangerBg: NSColor(hex: 0xD93025, alpha: 0.14),
        warning: NSColor(hex: 0xC77800),
        knob: NSColor.white
    )

    public static let dark = MintTheme(
        ink: NSColor(hex: 0xF2F2F0),
        ink2: NSColor(hex: 0x9A9A9F),
        // 4.5:1 (어두운 유리 합성 배경 ~0x1B1B1E 기준) — #29.
        // 과거 0x6E6E74는 3.4:1.
        ink3: NSColor(hex: 0x838389),
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
        // 어두운 배경 위에서는 지정색 그대로가 가장 잘 읽힌다 (~16:1).
        novel: NSColor(hex: accentSeed),
        novelBg: NSColor(hex: accentSeed, alpha: 0.18),
        danger: NSColor(hex: 0xFF453A),
        dangerBg: NSColor(hex: 0xFF453A, alpha: 0.18),
        warning: NSColor(hex: 0xFF9F0A),
        knob: NSColor.white
    )

    public static func of(_ scheme: ColorScheme) -> MintTheme {
        scheme == .dark ? .dark : .light
    }

    /// 사용자 팔레트를 입힌 테마 — 앱 화면은 전부 이 경로로 만든다.
    public static func of(_ scheme: ColorScheme, palette: MintPalette) -> MintTheme {
        of(scheme).tinted(with: palette, dark: scheme == .dark)
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
    public var dangerC: Color { Color(nsColor: danger) }
    public var dangerBgC: Color { Color(nsColor: dangerBg) }
    public var warningC: Color { Color(nsColor: warning) }
    public var knobC: Color { Color(nsColor: knob) }


    /// 토큰 전체 동등성 — `.equatable()`·조기 종료 등 diffing 최적화의 전제 (#54).
    public static func == (lhs: MintTheme, rhs: MintTheme) -> Bool {
        lhs.ink == rhs.ink && lhs.ink2 == rhs.ink2 && lhs.ink3 == rhs.ink3
            && lhs.ghost == rhs.ghost && lhs.blue == rhs.blue
            && lhs.sep == rhs.sep && lhs.sepStrong == rhs.sepStrong
            && lhs.hover == rhs.hover && lhs.activeBg == rhs.activeBg
            && lhs.chip == rhs.chip && lhs.chipBorder == rhs.chipBorder
            && lhs.pill == rhs.pill && lhs.pillBorder == rhs.pillBorder
            && lhs.kbd == rhs.kbd && lhs.codeBg == rhs.codeBg
            && lhs.glassWin == rhs.glassWin && lhs.toolbar == rhs.toolbar
            && lhs.sidebarTint == rhs.sidebarTint && lhs.statusbar == rhs.statusbar
            && lhs.activeLine == rhs.activeLine && lhs.selection == rhs.selection
            && lhs.selectionBorder == rhs.selectionBorder
            && lhs.novel == rhs.novel && lhs.novelBg == rhs.novelBg
            && lhs.danger == rhs.danger && lhs.dangerBg == rhs.dangerBg
            && lhs.warning == rhs.warning && lhs.knob == rhs.knob
    }
}

extension NSColor {
    /// 강조 배경(캡슐·배지) 위에서 WCAG AA(4.5:1)를 만족하는 전경색 —
    /// 검정·흰색 중 대비가 큰 쪽을 고른다. 밝은 라임 위 흰 글자(≈1.5:1) 문제의
    /// 일반해다 (이슈 #57).
    func accessibleForeground() -> NSColor {
        func luminance(_ c: NSColor) -> CGFloat {
            guard let s = c.usingColorSpace(.sRGB) else { return 0 }
            @inline(__always) func linear(_ v: CGFloat) -> CGFloat {
                v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(s.redComponent)
                + 0.7152 * linear(s.greenComponent)
                + 0.0722 * linear(s.blueComponent)
        }
        let l = luminance(self)
        // 검정 대비 (l+0.05)/0.05 ≥ 흰색 대비 1.05/(l+0.05) ⇔ l ≤ 0.179
        return l > 0.179 ? .black : .white
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// 저장용 24비트 hex — 컬러 피커에서 고른 색을 UserDefaults로 접는다.
    var hexValue: UInt32 {
        guard let srgb = usingColorSpace(.sRGB) else { return 0 }
        let r = UInt32((srgb.redComponent * 255).rounded())
        let g = UInt32((srgb.greenComponent * 255).rounded())
        let b = UInt32((srgb.blueComponent * 255).rounded())
        return (r << 16) | (g << 8) | b
    }

    /// sRGB 상대 명도 (WCAG) — 대비 계산의 재료.
    var relativeLuminance: CGFloat {
        guard let srgb = usingColorSpace(.sRGB) else { return 0 }
        func linear(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent)
            + 0.7152 * linear(srgb.greenComponent)
            + 0.0722 * linear(srgb.blueComponent)
    }

    /// WCAG 대비비 (1~21).
    func contrastRatio(against other: NSColor) -> CGFloat {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// **색상(hue)은 지키고 밝기만 옮겨** 배경 대비 목표를 맞춘 색.
    ///
    /// 왜 필요한가: 사용자 팔레트는 대비를 보장하지 않는다 — 기본 라이트
    /// 팔레트는 다섯 색이 전부 밝아 흰 배경 위 글자로 쓰면 안 보이고, 다크
    /// 팔레트는 전부 어두워 어두운 배경 위에서 사라진다. 팔레트의 색감은
    /// 유지하면서 읽히게 만드는 유일한 방법이 명도 조정이다.
    func adjustedForContrast(
        against background: NSColor, target: CGFloat = 4.5, darken: Bool
    ) -> NSColor {
        guard let hsb = usingColorSpace(.sRGB) else { return self }
        var brightness = hsb.brightnessComponent
        var result = self
        // 0.02씩 옮기며 목표 대비를 처음 넘는 지점에서 멈춘다 (최대 50회).
        for _ in 0..<50 {
            if result.contrastRatio(against: background) >= target { return result }
            brightness += darken ? -0.02 : 0.02
            if brightness < 0 || brightness > 1 { break }
            result = NSColor(
                hue: hsb.hueComponent,
                saturation: hsb.saturationComponent,
                brightness: brightness,
                alpha: hsb.alphaComponent)
        }
        return result
    }
}

// MARK: - 사용자 색상 팔레트

/// 사용자 색상 팔레트 — 밝기 순 5단계 (라이트/다크 각각 한 벌).
///
/// **배경·표면에만 쓴다.** 글자색(ink 계열)은 팔레트가 바뀌어도 그대로다 —
/// 가독성을 팔레트에 맡기면 읽을 수 없는 조합이 너무 쉽게 나온다. 액센트
/// (아이콘·강조 글자)만 팔레트에서 **색상은 물려받되 명도는 대비에 맞춰**
/// 파생한다 (`NSColor.adjustedForContrast`).
///
/// 슬롯 의미: 0 = 가장 넓은 면(창 유리·툴바), 4 = 가장 좁은 면(선택·활성 행).
public struct MintPalette: Equatable, Sendable, Codable {
    public var hexes: [UInt32]

    public static let slotCount = 5

    /// 슬롯 이름 — 설정 UI의 라벨.
    public static let slotLabels = ["창·툴바", "사이드바", "칩·배지", "액센트", "선택·강조"]

    public init(hexes: [UInt32]) {
        // 길이가 어긋난 저장값(구 버전·손상)에서도 UI가 무너지지 않게 보정한다.
        var fixed = Array(hexes.prefix(Self.slotCount))
        while fixed.count < Self.slotCount {
            fixed.append(MintPalette.lightDefault.hexes[fixed.count])
        }
        self.hexes = fixed
    }

    public static let lightDefault = MintPalette(
        hexes: [0xFFEC87, 0xE8E164, 0xE9FF7A, 0xB2EB7F, 0x9FFF92])

    public static let darkDefault = MintPalette(
        hexes: [0x618C03, 0x4F7302, 0x465902, 0x252601, 0x402929])

    public static func `default`(dark: Bool) -> MintPalette {
        dark ? .darkDefault : .lightDefault
    }

    public func color(_ slot: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(hex: hexes[min(max(slot, 0), Self.slotCount - 1)], alpha: alpha)
    }
}

extension MintTheme {
    /// 팔레트를 입힌 테마 — 배경·표면 슬롯만 갈아 끼운다.
    ///
    /// 알파는 기존 값의 구조를 따른다(넓은 면은 옅게, 좁은 면은 진하게) —
    /// 유리 배경 위에 얹히는 반투명 레이어라는 성질을 잃으면 창 전체가
    /// 납작해진다. 색만 바뀌고 레이어 관계는 그대로다.
    public func tinted(with palette: MintPalette, dark: Bool) -> MintTheme {
        // 액센트는 팔레트의 색상을 물려받되 대비를 맞춰 파생한다 — 라이트는
        // 어둡게(흰 바탕), 다크는 밝게(검은 바탕). 글자·아이콘에 쓰이므로
        // 팔레트 원색을 그대로 쓰면 읽히지 않는다.
        let accentBase = palette.color(3)
        let accent = accentBase.adjustedForContrast(
            against: dark ? NSColor(hex: 0x141416) : .white,
            target: 4.5, darken: !dark)

        return MintTheme(
            // 글자 계열 — 그대로.
            ink: ink, ink2: ink2, ink3: ink3, ghost: ghost, blue: blue,
            sep: sep, sepStrong: sepStrong, hover: hover,
            activeBg: palette.color(4, alpha: dark ? 0.30 : 0.35),
            chip: palette.color(2, alpha: dark ? 0.45 : 0.28),
            chipBorder: chipBorder,
            pill: palette.color(dark ? 4 : 0, alpha: dark ? 0.60 : 0.70),
            pillBorder: pillBorder,
            kbd: kbd, codeBg: codeBg,
            glassWin: palette.color(dark ? 3 : 0, alpha: dark ? 0.70 : 0.55),
            toolbar: palette.color(dark ? 3 : 0, alpha: dark ? 0.45 : 0.35),
            sidebarTint: palette.color(dark ? 2 : 1, alpha: dark ? 0.35 : 0.22),
            statusbar: palette.color(dark ? 3 : 0, alpha: dark ? 0.40 : 0.30),
            activeLine: palette.color(4, alpha: dark ? 0.18 : 0.18),
            selection: palette.color(4, alpha: dark ? 0.30 : 0.35),
            selectionBorder: accent.withAlphaComponent(0.45),
            novel: accent,
            novelBg: palette.color(3, alpha: dark ? 0.28 : 0.30),
            // 상태색(위험·주의)과 노브는 의미가 고정 — 팔레트에 물리지 않는다.
            danger: danger, dangerBg: dangerBg, warning: warning, knob: knob
        )
    }
}

/// 팔레트 보존 — UserDefaults에 hex 문자열로. 색은 파생 캐시가 아니라 사용자
/// 선택이므로 지식 사이드카(재구축 대상)가 아니라 설정에 산다.
@MainActor
public final class PaletteSettings: ObservableObject {
    public static let shared = PaletteSettings()

    /// 커스터마이징 사용 여부 — **기본은 꺼짐**이다.
    ///
    /// 꺼져 있으면 앱은 손대지 않은 기본 테마(유리 배경 + 연둣빛 액센트)로
    /// 그린다. 팔레트는 원하는 사람만 켜는 기능이지, 기본 외형을 대체하는
    /// 것이 아니다 — 켜지 않은 사용자가 색 때문에 놀랄 이유가 없다.
    @Published public var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Keys.enabled) }
    }

    @Published public var light: MintPalette {
        didSet {
            save(light, key: Keys.light)
            evaluateContrast()
        }
    }
    @Published public var dark: MintPalette {
        didSet {
            save(dark, key: Keys.dark)
            evaluateContrast()
        }
    }

    /// 저대비 경고 (#29) — 저장된 팔레트의 표면색 위에서 본문 잉크가 WCAG AA
    /// (4.5:1)를 못 만들면 Settings에 문장으로 알린다. 자동 보정은 하지 않는다 —
    /// 사용자가 고른 색을 몰래 바꾸는 것보다, 사실을 말고 고칠지 묻는 게
    /// "기억은 사용자의 것"(CLAUDE.md §1-5)과 같은 태도다. nil이면 문제 없음.
    @Published public private(set) var contrastWarning: String?

    /// 표면 후보(슬롯 0·2 = pill/glass 계열) 대비 최악값 검사.
    private func evaluateContrast() {
        guard enabled else {
            contrastWarning = nil
            return
        }
        func worstContrast(_ palette: MintPalette, ink: UInt32) -> Double {
            let surfaces = [palette.color(0), palette.color(2)]
                .compactMap { $0.usingColorSpace(.sRGB) }
            let inkLum = Self.relativeLuminance(ink)
            return surfaces.map { surface in
                // α 합성 근사 — 유리 위 흰/검 섞임을 절반 가정.
                let comps = surface.cgColor.alpha > 0.9
                    ? (surface.redComponent, surface.greenComponent, surface.blueComponent)
                    : (
                        surface.redComponent * 0.5 + 0.25,
                        surface.greenComponent * 0.5 + 0.25,
                        surface.blueComponent * 0.5 + 0.25
                    )
                func lin(_ v: CGFloat) -> Double {
                    let c = Double(v)
                    return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
                }
                let l = 0.2126 * lin(comps.0) + 0.7152 * lin(comps.1) + 0.0722 * lin(comps.2)
                return (max(l, inkLum) + 0.05) / (min(l, inkLum) + 0.05)
            }.min() ?? 10
        }
        let lightWorst = worstContrast(light, ink: 0x1C1C1E)
        let darkWorst = worstContrast(dark, ink: 0xF2F2F0)
        if lightWorst < 4.5 || darkWorst < 4.5 {
            contrastWarning = String(
                format: "이 팔레트는 본문 글자와 배경 대비가 %.1f:1이에요 — 작은 글자가 읽기 어려울 수 있어요 (권장 4.5:1 이상).",
                min(lightWorst, darkWorst))
        } else {
            contrastWarning = nil
        }
    }

    private static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF)
            + 0.7152 * channel((hex >> 8) & 0xFF)
            + 0.0722 * channel(hex & 0xFF)
    }

    private enum Keys {
        static let enabled = "mint.palette.enabled"
        static let light = "mint.palette.light"
        static let dark = "mint.palette.dark"
    }

    private init() {
        enabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        light = Self.load(Keys.light) ?? .lightDefault
        dark = Self.load(Keys.dark) ?? .darkDefault
        evaluateContrast()
    }

    public func palette(for scheme: ColorScheme) -> MintPalette {
        scheme == .dark ? dark : light
    }

    /// 파생 테마 캐시 — SwiftUI 패스마다 돌던 색변환 루프(tinted의 20여 회
    /// NSColor 생성+대비 보정)를 팔레트가 바뀔 때 1회로 묶는다 (#54).
    private var themeCache: (
        lightHexKey: String, darkHexKey: String, enabled: Bool,
        light: MintTheme, dark: MintTheme
    )?

    /// 화면이 쓸 테마 — 꺼져 있으면 기본 테마 그대로, 켜져 있으면 팔레트를 입힌다.
    public func theme(for scheme: ColorScheme) -> MintTheme {
        let lightKey = light.hexes.map { String($0, radix: 16) }.joined(separator: "|")
        let darkKey = dark.hexes.map { String($0, radix: 16) }.joined(separator: "|")
        if let cache = themeCache,
            cache.lightHexKey == lightKey, cache.darkHexKey == darkKey,
            cache.enabled == enabled
        {
            return scheme == .dark ? cache.dark : cache.light
        }
        let lightTheme = enabled ? MintTheme.of(.light, palette: light) : MintTheme.of(.light)
        let darkTheme = enabled ? MintTheme.of(.dark, palette: dark) : MintTheme.of(.dark)
        themeCache = (lightKey, darkKey, enabled, lightTheme, darkTheme)
        return scheme == .dark ? darkTheme : lightTheme
    }

    /// 기본값으로 되돌리기 — 색을 잘못 골라 UI가 안 보이게 됐을 때의 탈출구.
    public func reset(dark isDark: Bool) {
        if isDark { dark = .darkDefault } else { light = .lightDefault }
    }

    private static func load(_ key: String) -> MintPalette? {
        guard let raw = UserDefaults.standard.array(forKey: key) as? [String] else {
            return nil
        }
        let hexes = raw.compactMap { UInt32($0, radix: 16) }
        guard hexes.count == MintPalette.slotCount else { return nil }
        return MintPalette(hexes: hexes)
    }

    private func save(_ palette: MintPalette, key: String) {
        UserDefaults.standard.set(
            palette.hexes.map { String(format: "%06X", $0) }, forKey: key)
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
/// 모서리 반경 토큰 (#32) — 값은 기존 목업의 스케일을 그대로 이름에 붙인 것.
/// 새 UI는 이 토큰만 쓴다: "얼마나 둥글게"가 컴포넌트별 제멋대로 다르지 않게.
public enum MintRadius {
    /// 헤어라인 요소(작은 배지·삽입선 캡).
    public static let xs: CGFloat = 4
    /// 작은 칩·툴팁.
    public static let sm: CGFloat = 6
    /// 행·카드 기본 (8–10을 흡수).
    public static let md: CGFloat = 9
    /// 패널·시트 (11–12를 흡수).
    public static let lg: CGFloat = 12
}

/// 간격 단위 토큰 (#32) — 4pt 그리드 기준. 패딩 숫자의 의미를 통일한다.
public enum MintSpacing {
    public static let xs: CGFloat = 3
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 14
    public static let xl: CGFloat = 20
}

/// 고도(그림자) 토큰 (#32) — 유리 크롬의 미세한 층감. 색이 아니라 오프셋·블러 조합.
public enum MintElevation {
    /// 노브 같은 떠 있는 소형 요소.
    public static let raised = ShadowSpec(radius: 1.5, y: 1, opacity: 0.30)
    /// 토글 트랙 같은 얇은 면.
    public static let flat = ShadowSpec(radius: 1, y: 1, opacity: 0.14)

    public struct ShadowSpec: Sendable {
        public let radius: CGFloat
        public let y: CGFloat
        public let opacity: Double
    }
}

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
    ///
    /// `relativeTo:`로 시스템 글자 크기(Dynamic Type)에 연동한다 (#31) —
    /// 사용자가 크기를 키우면 크롬도 함께 커지고, 기본 배율은 지금과 같다.
    public static func serifUI(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let style = nearestTextStyle(for: size)
        if let family = serifFamily {
            return Font.custom(family, size: size, relativeTo: style).weight(weight)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    /// UI 산세리프 (SwiftUI) — Dynamic Type 연동 (#31).
    public static func uiFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let style = nearestTextStyle(for: size)
        if let family = uiFamily {
            return Font.custom(family, size: size, relativeTo: style).weight(weight)
        }
        // system(design:)에도 relativeTo 계열이 없으니 textStyle 이니셜라이저로.
        return .system(size: size, weight: weight, design: .default)
    }

    /// 모노 (상태·칩·kbd) — Dynamic Type 연동 (#31).
    public static func monoUI(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// pt → 가장 가까운 SwiftUI 텍스트 스타일 — relativeTo의 기준 (#31).
    nonisolated static func nearestTextStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<10.5: .caption2
        case ..<12.5: .caption
        case ..<14: .footnote
        case ..<16: .subheadline
        case ..<19: .body
        case ..<21: .title3
        case ..<23: .title2
        default: .title
        }
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


extension Color {
    /// SwiftUI 래퍼 — NSColor.accessibleForeground() 참조 (#57).
    var accessibleForegroundC: Color {
        Color(nsColor: NSColor(self).accessibleForeground())
    }
}
