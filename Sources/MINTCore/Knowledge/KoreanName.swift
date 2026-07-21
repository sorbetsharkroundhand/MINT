import Foundation

/// 한국어 인물명 정규화 — 조사·매개 "이" 규칙을 감지·별칭·Agent 조회가
/// 함께 쓰는 단일 지점이다 (PLAN §7, M12). 원형을 반드시 남겨 `순이`처럼
/// "이"로 끝나는 본명이 정규화 과정에서 사라지지 않게 한다.
public enum KoreanName {
    public static let minLength = 2
    public static let maxLength = 4

    /// 마지막 음절에 받침이 있는가 — 받침 이름 뒤 매개 "이"만 벗기기 위한 관문.
    public static func hasFinalConsonant(_ syllable: Character) -> Bool {
        guard syllable.unicodeScalars.count == 1,
            let scalar = syllable.unicodeScalars.first,
            (0xAC00...0xD7A3).contains(scalar.value)
        else { return false }
        return (scalar.value - 0xAC00) % 28 != 0
    }

    /// 순수 한글 2–4자인 이름꼴인가.
    public static func isNameShape(_ value: String) -> Bool {
        guard (minLength...maxLength).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy { (0xAC00...0xD7A3).contains($0.value) }
    }

    /// 표면형에서 가능한 이름 표기를 모두 펼친다. 가장 긴 조사 하나만 벗기며,
    /// 조사 제거 뒤와 원형 양쪽에서 받침 뒤 매개 "이" 제거형을 보존한다.
    public static func canonicalForms(
        _ surface: String, lexicon: CharacterLexicon = .base
    ) -> Set<String> {
        let value = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        var forms: Set<String> = []

        func add(_ candidate: String) {
            guard isNameShape(candidate) else { return }
            forms.insert(candidate)
            if let withoutI = removingIntermediaryI(candidate) {
                forms.insert(withoutI)
            }
        }

        add(value)
        if let particle = lexicon.particles.first(where: {
            value.count > $0.suffix.count && value.hasSuffix($0.suffix)
        }) {
            add(String(value.dropLast(particle.suffix.count)))
        }
        return forms
    }

    /// 조사와 매개 "이"를 벗긴 감지기용 어간. 가능한 이름이 여럿이면 조사 제거형,
    /// 그중 매개 "이" 제거형을 우선한다. 원형 보존은 조회용 canonicalForms가 맡는다.
    static func parsedStem(
        _ surface: String, removing particle: String? = nil
    ) -> String? {
        let base = particle.map { String(surface.dropLast($0.count)) } ?? surface
        if let withoutI = removingIntermediaryI(base) { return withoutI }
        return isNameShape(base) ? base : nil
    }

    /// 두 표면형이 같은 등록 인물을 가리킬 가능성이 있는가.
    public static func mayReferToSame(_ a: String, _ b: String) -> Bool {
        !canonicalForms(a).isDisjoint(with: canonicalForms(b))
    }

    private static func removingIntermediaryI(_ value: String) -> String? {
        guard value.count >= minLength + 1, value.last == "이" else { return nil }
        let stem = String(value.dropLast())
        guard let last = stem.last, hasFinalConsonant(last), isNameShape(stem) else { return nil }
        return stem
    }
}
