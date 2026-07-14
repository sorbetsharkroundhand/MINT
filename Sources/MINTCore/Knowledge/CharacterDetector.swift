import Foundation

/// 인물 후보 감지 — 결정적 깔때기 1단 (M6, PLAN §7).
///
/// **품사 없이 품사를 판별한다.** 한국어는 Apple 형태소 분석기가 품사·개체명을
/// 지원하지 않으므로(`CharacterLexicon` 참조), 교착어 구조로 대신한다:
///
/// 1. **격조사는 체언(명사·대명사)에만 붙는다.** 동사("걸었다")·형용사·부사
///    ("천천히")·접속사("그러나")는 격조사를 취하지 않는다 → 격 증거가 없으면
///    애초에 후보가 아니다. 이 하나로 비명사 대량 오탐이 구조적으로 사라진다.
/// 2. **여격(에게/한테/께)·호격(아/야)·발화 귀속("~가 말했다")은 유정물(사람)
///    에게만** 나타난다. 사물("일지"·"등불")은 격조사는 취해도 이 신호는 못
///    받는다 → **유정 신호를 인물 후보의 필수 조건**으로 삼아 명사 중에서도
///    사람만 남긴다. 이것이 Precision을 끌어올리는 핵심 레버다.
/// 3. 대명사("그녀")·호칭("소장님")은 구조로는 사람처럼 보이므로 닫힌 부류
///    목록으로 제외한다. 동음이의("소리"=소리/인물명)는 불용어로 뭉개지 않고
///    구조 신호(발화 귀속)가 실제 인물일 때만 통과시킨다.
///
/// 재현율보다 정밀도 우선(사용자 요구 + CLAUDE.md §2 품질>적극성): 유정 신호가
/// 하나도 없으면 침묵한다. 원고가 자라며 발화·여격이 생기면 다음 패스가 잡는다.
/// **등록은 언제나 사용자 확인**을 거치므로(CLAUDE.md §3) 남은 소수 오탐도 안전하다.
public enum CharacterDetector {

    /// 후보 하나 — 이름과 근거 수치 (확인 UI 문구 + 벤치 리포트용).
    public struct Candidate: Equatable, Sendable {
        public let name: String
        /// 전체 언급 횟수 (조사 변형 + 맨 이름 포함).
        public let mentions: Int
        /// 등장 씬 수.
        public let sceneCount: Int
        /// 유정 신호 횟수 (여격 + 호격 + 발화 귀속) — 이 값이 0이면 후보가 아니다.
        public let animacyHits: Int
        /// 서로 다른 격 역할 수 (명사다움 — 여러 역할로 격변화할수록 큼).
        public let caseRoleCount: Int
    }

    /// 임계 (PLAN §7) — 언급 5+ · 씬 3+. 씬이 적은 짧은 원고는 문서 씬 수까지 낮춘다.
    static let minMentions = 5
    static let minScenes = 3
    /// 이름 어간 길이 (한글) — 1자는 대명사·조사 파편, 5자↑은 구·문장 파편.
    static let minStemLength = 2
    static let maxStemLength = 4

    /// 어간별 누적 증거.
    private struct Evidence {
        var mentions = 0
        var scenes: Set<Int> = []
        var caseRoles: Set<CharacterLexicon.Role> = []
        var animacyHits = 0  // 여격 + 호격 + 발화 귀속
    }

    public static func detect(
        body: String,
        outline: DocumentOutline,
        known: Set<String>,
        rejected: Set<String>
    ) -> [Candidate] {
        guard !outline.scenes.isEmpty else { return [] }
        let lexicon = CharacterLexicon.current()
        let text = body as NSString
        var evidence: [String: Evidence] = [:]

        for (sceneIndex, scene) in outline.scenes.enumerated() {
            let sceneText = text.substring(
                with: NSRange(
                    location: scene.utf16Range.lowerBound,
                    length: scene.utf16Range.count))
            accumulate(
                sceneText, sceneIndex: sceneIndex,
                lexicon: lexicon, into: &evidence)
        }

        let excluded = lexicon.excluded
        let sceneThreshold = min(minScenes, outline.scenes.count)

        let candidates = evidence.compactMap { stem, ev -> Candidate? in
            guard (minStemLength...maxStemLength).contains(stem.count),
                ev.mentions >= minMentions,
                ev.scenes.count >= sceneThreshold,
                // ── 정밀도 레버: 유정 신호(사람만 받는 것)가 반드시 있어야 한다.
                ev.animacyHits >= 1,
                // ── 명사다움: 격조사를 취하는 체언이어야 한다(고정 낱말 배제).
                !ev.caseRoles.isEmpty,
                !known.contains(stem), !rejected.contains(stem),
                !excluded.contains(stem)
            else { return nil }
            return Candidate(
                name: stem, mentions: ev.mentions, sceneCount: ev.scenes.count,
                animacyHits: ev.animacyHits, caseRoleCount: ev.caseRoles.count)
        }

        // 랭킹: 유정 신호 > 격 다양성 > 빈도. 확인 UI는 맨 앞부터 하나씩 묻는다.
        // 상위 5개 컷 — 질문 줄을 세우지 않는다(품질 > 적극성).
        return Array(
            candidates
                .sorted {
                    ($0.animacyHits, $0.caseRoleCount, $0.mentions, $0.name)
                        > ($1.animacyHits, $1.caseRoleCount, $1.mentions, $1.name)
                }
                .prefix(5))
    }

    /// 한 씬을 훑어 어간별 증거를 누적한다. 토큰 순서를 보존해 "이름+주어표지"
    /// 다음 토큰의 발화 동사(대화 귀속)를 본다.
    private static func accumulate(
        _ sceneText: String, sceneIndex: Int,
        lexicon: CharacterLexicon, into evidence: inout [String: Evidence]
    ) {
        let words = hangulRuns(sceneText)
        for (i, word) in words.enumerated() {
            guard let parsed = parse(word, lexicon: lexicon) else { continue }
            let stem = parsed.stem
            var ev = evidence[stem] ?? Evidence()
            ev.mentions += 1
            ev.scenes.insert(sceneIndex)
            if let role = parsed.role {
                ev.caseRoles.insert(role)
                if role == .dative || role == .vocative { ev.animacyHits += 1 }
            }
            // 대화 귀속 — 주어 표지가 붙은 이름 뒤 1~2 토큰에 발화 동사가 오면 화자.
            if let role = parsed.role, role == .subject || role == .topic {
                let followers = words[(i + 1)..<min(i + 3, words.count)]
                if followers.contains(where: { next in
                    lexicon.speechVerbPrefixes.contains { next.hasPrefix($0) }
                }) {
                    ev.animacyHits += 1
                }
            }
            evidence[stem] = ev
        }
    }

    /// 한 토큰을 (어간, 격역할)로 분해한다. 격조사가 붙었으면 그 역할을,
    /// 안 붙은 맨 이름이면 role=nil로. 명사가 아닌 토큰(동사·부사 등)은 nil 반환.
    private static func parse(
        _ word: String, lexicon: CharacterLexicon
    ) -> (stem: String, role: CharacterLexicon.Role?)? {
        // 서술어 종결("~다")은 동사·형용사다 — 체언이 아니다.
        if word.hasSuffix("다") { return nil }

        for (suffix, role) in lexicon.particles where word.count > suffix.count {
            guard word.hasSuffix(suffix) else { continue }
            var stem = String(word.dropLast(suffix.count))
            // "서연이가/서연이는" — 받침 이름 뒤 매개 "이"까지 벗긴다(주격 이 제외).
            if role != .subject, stem.count >= minStemLength + 1, stem.hasSuffix("이") {
                stem = String(stem.dropLast())
            }
            guard isNameShape(stem) else { return nil }
            return (stem, role)
        }
        // 조사가 없는 맨 토큰 — 이름꼴이면 어간(맨 이름, 대화문 "도경."), 아니면 버림.
        guard isNameShape(word) else { return nil }
        return (word, nil)
    }

    /// 이름 어간의 형태 조건 — 순수 한글 2~4자.
    private static func isNameShape(_ stem: String) -> Bool {
        guard (minStemLength...maxStemLength).contains(stem.count) else { return false }
        return stem.unicodeScalars.allSatisfy { (0xAC00...0xD7A3).contains($0.value) }
    }

    /// 텍스트를 한글 최대 연속 토큰의 순서 있는 배열로 자른다(공백·문장부호 경계).
    private static func hangulRuns(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            if (0xAC00...0xD7A3).contains(scalar.value) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
