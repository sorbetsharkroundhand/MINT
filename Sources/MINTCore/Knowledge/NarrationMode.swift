import Foundation

/// 작품 전역 서술 시점 — 대사를 뺀 서술문의 주어 빈도에서 결정적으로 파생한다
/// (PLAN §7, M12). 근거가 약하면 추측하지 않고 `.unknown`으로 침묵한다.
public enum NarrationMode: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case firstPerson = "1인칭"
    case thirdPerson = "3인칭"
    case mixed = "혼합"
    case unknown = "미상"
}

public struct NarrationProfile: Codable, Equatable, Sendable {
    public var mode: NarrationMode
    public var narratorName: String?
    public var omniscientHint: Bool?
    public var firstPersonSubjectHits: Int
    public var thirdPersonProperNameSubjectHits: Int
    public var narrationSentenceCount: Int

    public init(
        mode: NarrationMode, narratorName: String? = nil,
        omniscientHint: Bool? = nil, firstPersonSubjectHits: Int = 0,
        thirdPersonProperNameSubjectHits: Int = 0, narrationSentenceCount: Int = 0
    ) {
        self.mode = mode
        self.narratorName = narratorName
        self.omniscientHint = omniscientHint
        self.firstPersonSubjectHits = firstPersonSubjectHits
        self.thirdPersonProperNameSubjectHits = thirdPersonProperNameSubjectHits
        self.narrationSentenceCount = narrationSentenceCount
    }

    /// 프롬프트·바이블이 공유하는 보수적인 표시 문자열.
    public var displayText: String {
        switch mode {
        case .firstPerson:
            return narratorName.map { "1인칭 (서술자: \($0))" } ?? "1인칭 서술자"
        case .thirdPerson:
            if omniscientHint == true { return "3인칭 전지적" }
            if omniscientHint == false { return "3인칭 제한적" }
            return "3인칭"
        case .mixed: return "혼합 시점"
        case .unknown: return "미상"
        }
    }

    public var agentPOV: String? { mode == .unknown ? nil : displayText }
}

/// 씬 해시별 통계를 메모해 원문 한 조각만 바뀌면 그 조각만 다시 센다. 이 계산은
/// BackgroundIndexer가 스냅샷을 조립할 때 수행되며 예측 경로에는 들어오지 않는다.
public enum NarrationAnalyzer {
    private struct Evidence: Sendable {
        var first = 0
        var weakFirst = 0
        var third = 0
        var sentences = 0
        var interiorCharacters: Set<UUID> = []
        var vocatives: [UUID: Int] = [:]

        var weightedFirst: Int { first + weakFirst / 2 }
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Evidence] = [:]

    public static func analyze(
        body: String, outline: DocumentOutline,
        characters: [CharacterCard] = [], insights: [String: SceneInsights] = [:]
    ) -> NarrationProfile {
        let source = body as NSString
        let characterKey = characters.flatMap { [$0.name, $0.aliases] }.joined(separator: "|")
        var total = Evidence()
        var chapters: [String: Evidence] = [:]

        for scene in outline.scenes {
            let range = NSRange(
                location: scene.utf16Range.lowerBound, length: scene.utf16Range.count)
            guard NSMaxRange(range) <= source.length else { continue }
            let cacheKey = scene.contentHash + "|" + DocumentOutline.stableHash(characterKey)
            let evidence: Evidence
            cacheLock.lock()
            let cached = cache[cacheKey]
            cacheLock.unlock()
            if let cached {
                evidence = cached
            } else {
                evidence = count(in: source.substring(with: range), characters: characters)
                cacheLock.lock()
                cache[cacheKey] = evidence
                if cache.count > 2_000 { cache.removeAll(keepingCapacity: true) }
                cacheLock.unlock()
            }
            merge(evidence, into: &total)
            let chapter = scene.headingPath.first ?? "__root"
            merge(evidence, into: &chapters[chapter, default: Evidence()])
        }

        // LLM이 이미 직접 근거를 뽑은 앎도 전지/제한 근사의 보조 증거로 쓴다.
        for insight in insights.values {
            for delta in insight.knowledge { total.interiorCharacters.insert(delta.characterID) }
        }

        let chapterModes = chapters.values.map(classify).filter { $0 != .unknown }
        let distinct = Set(chapterModes)
        let mode: NarrationMode
        if distinct.contains(.firstPerson) && distinct.contains(.thirdPerson) {
            mode = .mixed
        } else {
            mode = classify(total)
        }
        let omniscient: Bool?
        if mode == .thirdPerson {
            if total.interiorCharacters.count >= 2 { omniscient = true }
            else if total.interiorCharacters.count == 1 { omniscient = false }
            else { omniscient = nil }
        } else {
            omniscient = nil
        }
        let narratorName: String?
        if mode == .firstPerson,
            let best = total.vocatives.max(by: { $0.value < $1.value }), best.value >= 2,
            total.vocatives.values.filter({ $0 == best.value }).count == 1
        {
            narratorName = characters.first { $0.id == best.key }?.name
        } else {
            narratorName = nil
        }
        return NarrationProfile(
            mode: mode, narratorName: narratorName, omniscientHint: omniscient,
            firstPersonSubjectHits: total.weightedFirst,
            thirdPersonProperNameSubjectHits: total.third,
            narrationSentenceCount: total.sentences)
    }

    private static func classify(_ evidence: Evidence) -> NarrationMode {
        guard evidence.sentences >= 3 else { return .unknown }
        let first = evidence.weightedFirst
        let third = evidence.third
        let firstRatio = Double(first) / Double(evidence.sentences)
        let thirdRatio = Double(third) / Double(evidence.sentences)
        // 1인칭 소설에서도 다른 인물은 당연히 3인칭 주어로 등장한다. 두 신호가
        // 한 장에 함께 있다는 이유만으로 혼합으로 만들지 않는다. 혼합은 위의
        // 장별 판정 불일치에서만 확정하고, 강한 1인칭 자기지칭을 우선한다.
        if first >= 2, firstRatio >= 0.15 { return .firstPerson }
        if third >= 2, thirdRatio >= 0.15, first <= 1 { return .thirdPerson }
        return .unknown
    }

    private static func merge(_ source: Evidence, into target: inout Evidence) {
        target.first += source.first
        target.weakFirst += source.weakFirst
        target.third += source.third
        target.sentences += source.sentences
        target.interiorCharacters.formUnion(source.interiorCharacters)
        for (id, count) in source.vocatives { target.vocatives[id, default: 0] += count }
    }

    private static func count(in text: String, characters: [CharacterCard]) -> Evidence {
        let narration = removingDialogue(from: text)
        let sentences = narration.split(whereSeparator: { ".!?。！？\n".contains($0) })
            .map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var result = Evidence()
        result.sentences = sentences.count
        let firstSignals: Set<String> = ["나는", "내가", "나도", "난", "저는", "제가", "저도", "전"]
        let weakSignals: Set<String> = ["우리는", "우리가", "우리도", "우린"]
        let thirdPronouns: Set<String> = ["그는", "그가", "그도", "그녀는", "그녀가", "그녀도"]
        let thoughtPrefixes = ["생각", "느꼈", "느끼", "깨달", "떠올", "마음속", "알았다", "몰랐다"]

        for sentence in sentences {
            let tokens = hangulRuns(sentence)
            result.first += tokens.filter(firstSignals.contains).count
            result.weakFirst += tokens.filter(weakSignals.contains).count
            result.third += tokens.filter(thirdPronouns.contains).count
            for card in characters {
                let names = [card.name] + card.aliases.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let isSubject = tokens.contains { token in
                    names.contains { name in subjectToken(token, refersTo: name) }
                }
                if isSubject {
                    result.third += 1
                    if thoughtPrefixes.contains(where: sentence.contains) {
                        result.interiorCharacters.insert(card.id)
                    }
                }
            }
        }
        // 1인칭 원고에서 다른 인물이 반복해 부르는 유일한 등록 이름은 화자명
        // 후보가 된다. 한 번뿐이거나 동률이면 이름을 지어내지 않고 nil을 유지한다.
        for dialogue in dialogueFragments(from: text) {
            let tokens = hangulRuns(dialogue)
            for card in characters {
                let names = [card.name] + card.aliases.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if tokens.contains(where: { token in
                    names.contains(where: { name in vocativeToken(token, refersTo: name) })
                }) {
                    result.vocatives[card.id, default: 0] += 1
                }
            }
        }
        return result
    }

    private static func subjectToken(_ token: String, refersTo name: String) -> Bool {
        for particle in CharacterLexicon.base.particles
        where particle.role == .subject || particle.role == .topic {
            guard token.count > particle.suffix.count, token.hasSuffix(particle.suffix) else { continue }
            let stem = String(token.dropLast(particle.suffix.count))
            if KoreanName.mayReferToSame(stem, name) { return true }
        }
        return false
    }

    private static func vocativeToken(_ token: String, refersTo name: String) -> Bool {
        for particle in CharacterLexicon.base.particles where particle.role == .vocative {
            guard token.count > particle.suffix.count, token.hasSuffix(particle.suffix) else { continue }
            let stem = String(token.dropLast(particle.suffix.count))
            if KoreanName.mayReferToSame(stem, name) { return true }
        }
        return false
    }

    /// 따옴표 안은 공백으로 바꿔 문장 경계를 보존하되 대사의 "나는"은 세지 않는다.
    private static func removingDialogue(from text: String) -> String {
        let opening: [Character: Character] = ["“": "”", "「": "」", "『": "』", "\"": "\""]
        var closing: Character?
        var result = ""
        for character in text {
            if let expected = closing {
                if character == expected { closing = nil }
                result.append(character == "\n" ? "\n" : " ")
            } else if let expected = opening[character] {
                closing = expected
                result.append(" ")
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func dialogueFragments(from text: String) -> [String] {
        let opening: [Character: Character] = ["“": "”", "「": "」", "『": "』", "\"": "\""]
        var closing: Character?
        var current = ""
        var result: [String] = []
        for character in text {
            if let expected = closing {
                if character == expected {
                    if !current.isEmpty { result.append(current) }
                    current = ""
                    closing = nil
                } else {
                    current.append(character)
                }
            } else if let expected = opening[character] {
                closing = expected
            }
        }
        return result
    }

    private static func hangulRuns(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            if (0xAC00...0xD7A3).contains(scalar.value) { current.unicodeScalars.append(scalar) }
            else if !current.isEmpty { result.append(current); current = "" }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
