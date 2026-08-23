import Foundation

/// 실사용 수락률 지표 (M7, PLAN §13 온라인 지표) — **로컬 전용, 원격 전송 절대
/// 금지** (CLAUDE.md §1-3). `~/Documents/MINT/metrics.jsonl`에 한 줄 한 사건.
///
/// 왜 지금인가: M6 측정에서 접두 일치 프록시가 지식 주입에 둔감하다는 결론이
/// 났고(docs/m6-knowledge.md), 실사용 수락률이 품질의 **본 지표**로 승격됐다.
/// 문단 제안(PLAN §10 정지 사다리)도 "수락률 데이터로 확신이 서기 전엔 열지
/// 않는다"— 이 로그가 그 데이터의 원천이다.
///
/// 기록은 제안 단위 사건(노출·수락·거절)이라 분당 몇 건 수준 — 키 입력 경로가
/// 아니다. 그래도 파일 IO는 전용 직렬 큐로 보내 메인을 안 막는다.
public enum AcceptanceMetrics {

    public enum Event: String, Sendable {
        case shown  // 고스트가 화면에 나타남
        case acceptedFull = "accepted_full"  // Tab 전체 수락
        case acceptedWord = "accepted_word"  // → 한 단어 수락 (단어마다 1건)
        case dismissed  // 편집·Esc·커서 이동으로 사라짐
    }

    private static let queue = DispatchQueue(
        label: "mint.metrics", qos: .utility)

    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("MINT/metrics.jsonl", isDirectory: false)
    }

    /// 사건 한 줄 append — 실패는 조용히 버린다 (지표가 글쓰기를 방해하면 본말전도).
    public static func log(_ event: Event, mode: String, latencyMs: Int? = nil) {
        let timestamp = ISO8601DateFormatter().string(from: .now)
        var line = #"{"ts":"\#(timestamp)","event":"\#(event.rawValue)","mode":"\#(mode)""#
        if let latencyMs { line += #","latencyMs":\#(latencyMs)"# }
        line += "}\n"
        // 비동기 블록엔 값 스냅샷을 넘긴다 — var 캡처는 동시성 검사의 경고 대상.
        let payload = line
        queue.async {
            guard let data = payload.data(using: .utf8) else { return }
            let url = fileURL
            if !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url)
                return
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    // MARK: - 열람·삭제 (Settings, PLAN §13 "열람·삭제 가능")

    public struct Summary: Equatable, Sendable {
        public var shown = 0
        public var acceptedFull = 0
        public var acceptedWord = 0
        public var dismissed = 0
        /// 모드별 (노출, 전체 수락) — story가 fast보다 나은지가 M6→M7 이관 질문.
        public var byMode: [String: (shown: Int, accepted: Int)] = [:]

        /// 전체 수락률 (%) — 노출 대비 Tab 수락. 단어 수락은 부분 신호라 따로 본다.
        public var acceptanceRate: Int {
            shown > 0 ? Int((Double(acceptedFull) / Double(shown) * 100).rounded()) : 0
        }

        public static func == (lhs: Summary, rhs: Summary) -> Bool {
            lhs.shown == rhs.shown && lhs.acceptedFull == rhs.acceptedFull
                && lhs.acceptedWord == rhs.acceptedWord && lhs.dismissed == rhs.dismissed
                && lhs.byMode.keys.sorted() == rhs.byMode.keys.sorted()
        }
    }

    /// 파일 집계 — 백그라운드 스레드에서 부를 것 (Settings의 .task가 부른다).
    /// 파서는 관대하게: 깨진 줄은 건너뛴다 (지표는 근사면 충분).
    public static func summarize() -> Summary {
        var summary = Summary()
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return summary
        }
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let eventRaw = json["event"] as? String,
                let event = Event(rawValue: eventRaw)
            else { continue }
            let mode = json["mode"] as? String ?? "?"
            var modeStats = summary.byMode[mode] ?? (0, 0)
            switch event {
            case .shown:
                summary.shown += 1
                modeStats.shown += 1
            case .acceptedFull:
                summary.acceptedFull += 1
                modeStats.accepted += 1
            case .acceptedWord: summary.acceptedWord += 1
            case .dismissed: summary.dismissed += 1
            }
            summary.byMode[mode] = modeStats
        }
        return summary
    }

    /// 지표 삭제 — 파일을 지운다. 원고와 무관한 파생 기록이라 확인 없이 안전.
    public static func reset() {
        queue.async { try? FileManager.default.removeItem(at: fileURL) }
    }
}
