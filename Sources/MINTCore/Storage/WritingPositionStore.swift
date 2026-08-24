import Foundation

/// 문서별 마지막 집필 위치 (이슈 #36) — **UI 상태**다. 원문(entries.json)이 아니라
/// UserDefaults에 산다: 파생 캐시는 아니지만 사용자 저작도 아닌 창 상태이고,
/// 지워져도 원문은 무사하다.
///
/// 저장 값은 커서 위치만이 아니라 **주변 문맥 앵커**(직전·이후 최대 24자)를 함께
/// 담는다 — 편집으로 위치가 밀렸을 때 정확한 clamp 대신 앵커로 재안착(re-anchor)
/// 하기 위해서다. "3장 중간을 고치던 자리"는 문자 오프셋보다 문맥으로 찾는 게 맞다.
///
/// IME 조합(marked text)·임시 선택은 저장하지 않는다 — 확정되지 않은 한글 조합
/// 중간 위치를 복원하면 깨진 글자 자리로 뛰는 꼴이 된다 (#36 완료 조건 4).
@MainActor
public final class WritingPositionStore {

    public struct Position: Codable, Equatable, Sendable {
        /// 커서 UTF-16 위치 — 저장 시점 기준.
        public var location: Int
        /// 커서 직전 본문 조각(≤24자) — 재안착 키.
        public var before: String
        /// 커서 위치부터의 본문 조각(≤24자) — 재안착 검증.
        public var after: String
    }

    public static let shared = WritingPositionStore()

    static let maxEntries = 200

    private let defaults: UserDefaults
    private let key = "mint.writingPositions"
    private(set) var positions: [UUID: Position] = [:]
    private var persistTask: Task<Void, Never>?
    /// 디스크 쓰기 디바운스 — 타이핑마다 UserDefaults를 치지 않게.
    private let persistDelay: Duration

    init(defaults: UserDefaults = .standard, persistDelay: Duration = .seconds(2)) {
        self.defaults = defaults
        self.persistDelay = persistDelay
        if let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([UUID: Position].self, from: data)
        {
            positions = decoded
        }
    }

    func position(for entryID: UUID) -> Position? {
        positions[entryID]
    }

    /// 현재 위치를 기록한다. `marked`가 true면(IME 조합 중) 무시한다 (#36).
    func record(
        entryID: UUID, location: Int, before: String, after: String,
        marked: Bool
    ) {
        guard !marked else { return }
        // LRU — 오래된 문서부터 잘라 상한 유지 (UserDefaults 비용 보호).
        if positions[entryID] == nil, positions.count >= Self.maxEntries {
            // 삽입 순서가 없으므로 가장 단순히 절반을 버린다 — 200건은 수년치다.
            if positions.count > Self.maxEntries / 2 {
                let doomed = Array(positions.keys.prefix(positions.count - Self.maxEntries / 2))
                for id in doomed { positions.removeValue(forKey: id) }
            }
        }
        positions[entryID] = Position(
            location: location,
            before: String(before.suffix(24)),
            after: String(after.prefix(24)))
        schedulePersist()
    }

    /// 텍스트가 바뀐 뒤의 복원 위치를 푼다 — 재안착 사다리 (#36):
    /// 1. 저장 위치 그대로 유효하고 문맥이 일치 → 그대로.
    /// 2. 위치가 어긋났으면 `before` 꼬리(최근 12자)를 본문에서 찾아 그 끝으로.
    /// 3. 못 찾으면 nil — 문서 맨 위 규칙(load 기본 동작)을 따른다.
    func resolve(for entryID: UUID, in text: String) -> Int? {
        guard let p = positions[entryID] else { return nil }
        let ns = text as NSString
        let length = ns.length
        if p.location <= length {
            let beforeStart = max(0, p.location - p.before.utf16.count)
            let beforeMatches =
                ns.substring(with: NSRange(location: beforeStart, length: p.location - beforeStart))
                .hasSuffix(p.before)
            let afterEnd = min(length, p.location + p.after.utf16.count)
            let afterMatches =
                ns.substring(with: NSRange(location: p.location, length: afterEnd - p.location))
                .hasPrefix(p.after)
            if beforeMatches && afterMatches { return p.location }
        }
        // 재안착 — before 꼬리로. 짧은 앵커일수록 허위 적중이 늘지만, 12자 연속
        // 일치가 허위일 확률은 한국어 장편에서 무시할 수준이다.
        let anchor = String(p.before.suffix(12))
        if anchor.utf16.count >= 4 {
            var searchRange = NSRange(location: 0, length: length)
            var best: Int?
            while searchRange.location < length {
                let found = ns.range(of: anchor, range: searchRange)
                guard found.location != NSNotFound else { break }
                best = found.upperBound  // 마지막 등장 — 최근에 쓴 자리일 가능성.
                searchRange.location = found.upperBound
                searchRange.length = length - found.upperBound
            }
            if let restored = best { return restored }
        }
        return nil
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: self?.persistDelay ?? .seconds(2))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    /// 즉시 디스크 반영 — 앱 종료 훅(AppDelegate flush 경로)에서 호출.
    public func persistNow() {
        persistTask?.cancel()
        persistTask = nil
        guard let data = try? JSONEncoder().encode(positions) else { return }
        defaults.set(data, forKey: key)
    }

    /// 테스트 격리 — 사용자 실제 UserDefaults를 건드리지 않게.
    func _testReset() {
        positions = [:]
        defaults.removeObject(forKey: key)
    }
}
