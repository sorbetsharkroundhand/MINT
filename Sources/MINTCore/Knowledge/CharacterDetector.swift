import Foundation

/// 인물 후보 감지 — 결정적 깔때기 1단 (M6, PLAN §7).
///
/// LLM 없이 빈도·조사 휴리스틱만으로 후보를 뽑는다 (CLAUDE.md §2-5 —
/// 정규식·통계로 되는 일에 토큰을 쓰지 않는다). 오탐은 깔때기의 다음 단이
/// 거른다: **등록은 반드시 사용자 확인**을 거치므로(CLAUDE.md §3) 여기서는
/// 재현율보다 "그럴듯한 후보만 조용히" 내는 정밀도를 우선한다.
public enum CharacterDetector {

    /// 후보 하나 — 이름과 근거 수치 (확인 UI 문구용).
    public struct Candidate: Equatable, Sendable {
        public let name: String
        /// 전체 언급 횟수 (조사 변형 포함).
        public let mentions: Int
        /// 등장 씬 수 — 여러 씬에 걸쳐야 "지나가는 단어"가 아니다.
        public let sceneCount: Int
    }

    /// 임계 (PLAN §7 예시값) — 씬 3+ · 언급 5+. 씬이 적은 짧은 원고는
    /// 씬 요건을 문서 씬 수까지 낮춘다 (첫 장부터 감지가 아예 침묵하지 않게).
    static let minMentions = 5
    static let minScenes = 3

    /// 이름 뒤에 붙는 조사 — 붙은 형태("서연이가")를 어간("서연")으로 접는다.
    /// 긴 것 먼저 매칭 (예: "에게서"가 "에"보다 먼저).
    private static let particles = [
        "이에게서", "에게서", "이라고", "라고", "한테서", "에게", "한테", "께서",
        "이랑", "랑", "하고", "에서", "에는", "에도", "으로", "로", "에", "이면",
        "과", "와", "의", "은", "는", "이", "가", "을", "를",
        "도", "만", "아", "야", "처럼", "보다", "부터", "까지", "이다", "이었다",
    ]

    /// 사람 이름일 수 없는 흔한 낱말 — 호칭·대명사·시간·일반명사.
    /// 완전한 목록이 아니다 — 최종 방어선은 사용자 확인이다.
    private static let stopwords: Set<String> = [
        "그것", "이것", "저것", "우리", "당신", "자신", "그녀", "그는", "그가",
        "사람", "생각", "소리", "시간", "오늘", "어제", "내일", "지금", "이제",
        "하나", "다시", "함께", "모두", "정말", "그냥", "아직", "이미", "가장",
        "얼굴", "마음", "이야기", "말씀", "아버지", "어머니", "할아버지", "할머니",
        "아저씨", "아주머니", "선생님", "소장님", "그날", "그때", "여기", "거기",
        "저기", "무엇", "누구", "어디", "언제",
    ]

    /// 본문에서 인물 후보를 뽑는다. `known`(이미 등록된 이름·별칭)과
    /// `rejected`(사용자가 무시한 이름)는 후보에서 뺀다 — 같은 후보 재질문
    /// 금지 (PLAN §7).
    public static func detect(
        body: String,
        outline: DocumentOutline,
        known: Set<String>,
        rejected: Set<String>
    ) -> [Candidate] {
        guard !outline.scenes.isEmpty else { return [] }
        let text = body as NSString

        // 씬별로 토큰을 접어 (어간 → 언급 수, 등장 씬 집합)을 만든다.
        var mentions: [String: Int] = [:]
        var scenes: [String: Set<Int>] = [:]
        for (sceneIndex, scene) in outline.scenes.enumerated() {
            let sceneText = text.substring(
                with: NSRange(
                    location: scene.utf16Range.lowerBound,
                    length: scene.utf16Range.count))
            for token in tokens(in: sceneText) {
                guard let stem = stem(of: token) else { continue }
                mentions[stem, default: 0] += 1
                scenes[stem, default: []].insert(sceneIndex)
            }
        }

        let sceneThreshold = min(minScenes, outline.scenes.count)
        let candidates = mentions.compactMap { stem, count -> Candidate? in
            guard count >= minMentions,
                let sceneSet = scenes[stem], sceneSet.count >= sceneThreshold,
                !known.contains(stem), !rejected.contains(stem)
            else { return nil }
            return Candidate(name: stem, mentions: count, sceneCount: sceneSet.count)
        }
        // 언급 많은 순 — 확인 UI는 맨 앞 하나씩만 묻는다 (조용한 UX).
        // 상위 5개까지만: 일반명사 오탐이 섞이는 걸 알기에 질문 줄을 세우지
        // 않는다 (품질 > 적극성). 나머지는 원고가 자라며 다음 패스에 다시 온다.
        return Array(
            candidates
                .sorted { ($0.mentions, $0.name) > ($1.mentions, $1.name) }
                .prefix(5))
    }

    /// 한글 연속 토큰 (2–5자에 조사가 붙은 꼴까지 고려해 2–8자).
    private static func tokens(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            if (0xAC00...0xD7A3).contains(scalar.value) {
                current.unicodeScalars.append(scalar)
            } else {
                if (2...8).contains(current.count) { result.append(current) }
                current = ""
            }
        }
        if (2...8).contains(current.count) { result.append(current) }
        return result
    }

    /// 토큰에서 이름 어간을 뽑는다 — 조사 제거 후 2–4자 한글이면 후보 어간.
    ///
    /// "서연이가"→"서연", "도경은"→"도경". 조사가 안 붙은 맨 이름("서연")도
    /// 그대로 어간이다. 규칙:
    /// - 조사가 붙었으면 **벗긴 형태만** 어간 후보다 — "눈이"가 "눈"이 짧다고
    ///   "눈이"로 남으면 조사 낀 오탐이 산다.
    /// - 가장 많이 벗긴 형태가 흔한 낱말(stopwords)이면 토큰 전체를 버린다 —
    ///   "소리는"은 이름이 아니라 명사 "소리"+조사다.
    /// - "~다"로 끝나는 토큰은 서술어(있었다·말했다)로 보고 버린다.
    /// 한계: 형태소 분석이 아니라서 일반명사가 새어 들어온다 — 임계(여러 씬 ×
    /// 여러 조사 변형)·상위 5개 컷·사용자 확인이 거른다.
    private static func stem(of token: String) -> String? {
        guard !token.hasSuffix("다") else { return nil }
        var candidates = [token]
        for particle in particles where token.hasSuffix(particle) {
            let stem = String(token.dropLast(particle.count))
            // 조사를 찾았으면 원형은 더 이상 후보가 아니다.
            candidates = [stem]
            // "서연이가" 꼴 — 받침 이름 뒤 매개 "이"까지 벗긴 형태가 더 우선.
            if particle.first != "이", stem.hasSuffix("이"), stem.count >= 3 {
                candidates.insert(String(stem.dropLast()), at: 0)
            }
            break  // 긴 조사 우선 — 첫 매칭이 가장 길다
        }
        for candidate in candidates {  // 가장 많이 벗긴 쪽 우선
            if stopwords.contains(candidate) { return nil }  // 흔한 낱말 + 조사
            if (2...4).contains(candidate.count) { return candidate }
        }
        return nil
    }
}
