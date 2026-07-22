import Foundation

/// 일관성 경고 하나 (M7, PLAN §14 "공저자") — 본문 위치를 물고 있어 UI가
/// 해당 자리를 가리킬 수 있다.
public struct ConsistencyWarning: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case deadSpeaker = "죽은 인물 발화"
        case honorificBreak = "말투 붕괴"
    }

    public var kind: Kind
    public var characterID: UUID
    /// 문제가 감지된 본문 위치 (UTF-16).
    public var utf16Position: Int
    /// 사용자에게 보여줄 한 줄 설명 — 단정이 아니라 확인 요청의 어조.
    public var message: String

    public var id: String {
        "\(kind.rawValue)-\(characterID.uuidString)-\(utf16Position)"
    }
}

/// 일관성 검사기 (M7, PLAN §14) — **결정적, LLM 없음** (CLAUDE.md §2-5).
///
/// 예측 우선순위 1번 "일관성 유지"(CLAUDE.md §3)의 열람 면이다: 죽은 인물이
/// 말하거나 확립된 존대가 무너지는 것은 유창해도 실패다 — 프롬프트가 막는 것
/// (카드의 생사 상태·존대쌍 주입)과 같은 지식으로, 이미 쓰인 원문도 검사한다.
///
/// **비침습 원칙**: 경고는 사이드바 배지·목록으로만 보인다. 본문에 밑줄을 긋거나
/// 팝업을 띄우지 않는다 — 회상·의도적 반말 트기처럼 **작가가 옳은 경우**가
/// 항상 있으므로, 경고는 단정이 아니라 "확인해 보세요"다 (품질 > 적극성).
public enum ConsistencyChecker {
    /// 존대 붕괴 판정에 필요한 최소 선행 발화 수 — 두어 번의 우연으로
    /// "확립됐다"고 단정하지 않는다.
    static let minEstablishedUtterances = 3

    /// 생사 델타 값에서 사망을 읽는 닫힌 규칙 — "죽을 뻔했다" 같은 서술을
    /// 사망으로 오판하지 않게 보수적으로 잡는다.
    static func isDead(_ vitality: String) -> Bool {
        vitality.contains("사망") || vitality == "죽음" || vitality.hasPrefix("죽었")
    }

    /// 스냅샷 전체 검사 — 발화 수에 선형. 스냅샷 발행 시 백그라운드에서 한 번
    /// 돌고 결과만 UI로 간다 (키 입력·렌더 경로에서 재계산 금지).
    public static func check(
        snapshot: KnowledgeSnapshot, characters: [CharacterCard]
    ) -> [ConsistencyWarning] {
        let names = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0.name) })
        var warnings: [ConsistencyWarning] = []

        // ① 죽은 인물 발화 — 발화 시점 이전의 생사 fold가 사망이면 경고.
        // 시점 차단(fold가 커서 이전만 접는 것)이 그대로 "죽기 전 발화는 정상,
        // 죽은 뒤 발화만 경고"를 만든다. 인물당 첫 건만 — 같은 문제의 반복
        // 경고는 소음이다.
        var deadReported: Set<UUID> = []
        for utterance in snapshot.utterances {
            guard !deadReported.contains(utterance.speakerID) else { continue }
            let state = snapshot.stateAt(of: utterance.speakerID, before: utterance.utf16Start)
            guard let vitality = state[.vitality], isDead(vitality) else { continue }
            deadReported.insert(utterance.speakerID)
            let name = names[utterance.speakerID] ?? "등장인물"
            warnings.append(
                ConsistencyWarning(
                    kind: .deadSpeaker,
                    characterID: utterance.speakerID,
                    utf16Position: utterance.utf16Start,
                    message: "\(name)이(가) '\(vitality)' 상태로 기록된 뒤에 대사가 있어요 — 회상이 아니라면 확인해 보세요"
                )
            )
        }

        // ② 존대 붕괴 — (화자→청자) 쌍에서 같은 존대가 3회 이상 이어진 뒤
        // 반대 존대가 나오면 경고. 쌍당 첫 건만 — 반말 트기(의도적 전환)면
        // 그 뒤는 새 관계다.
        struct PairKey: Hashable { let speaker: UUID; let listener: UUID }
        var streak: [PairKey: (politeness: Politeness, count: Int)] = [:]
        var breakReported: Set<PairKey> = []
        for utterance in snapshot.utterances {
            guard let listener = utterance.listenerID,
                  let politeness = utterance.politeness
            else { continue }
            let key = PairKey(speaker: utterance.speakerID, listener: listener)
            if let current = streak[key] {
                if current.politeness == politeness {
                    streak[key] = (politeness, current.count + 1)
                } else {
                    if current.count >= minEstablishedUtterances,
                       !breakReported.contains(key) {
                        breakReported.insert(key)
                        let speaker = names[utterance.speakerID] ?? "등장인물"
                        let target = names[listener] ?? "상대"
                        warnings.append(
                            ConsistencyWarning(
                                kind: .honorificBreak,
                                characterID: utterance.speakerID,
                                utf16Position: utterance.utf16Start,
                                message: "\(speaker)이(가) \(target)에게 \(current.politeness.rawValue)을 쓰다 \(politeness.rawValue)로 바뀌었어요 — 의도한 변화가 아니라면 확인해 보세요"
                            )
                        )
                    }
                    streak[key] = (politeness, 1) // 전환 후는 새 확립의 시작
                }
            } else {
                streak[key] = (politeness, 1)
            }
        }

        return warnings.sorted { $0.utf16Position < $1.utf16Position }
    }
}
