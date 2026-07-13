import CryptoKit
import Foundation

/// 작품 아웃라인 — 마크다운 헤딩(`#`·`##`·`###`)을 장·절·씬 트리로 읽는
/// 결정적 파서 (PLAN §5). LLM 없음 (CLAUDE.md §2-5).
///
/// 사용자의 헤딩 구조가 곧 타임라인 골격이다 (PLAN §8):
/// - 씬 배열 순서(담화 순서)가 v1의 시간축 — `scenes(upTo:)`가 "커서 이전
///   지식만 주입"(CLAUDE.md §2-4) 질의의 원형이다.
/// - 씬별 콘텐츠 해시는 M6 증분 파이프라인(더티 추적·추출 메모이제이션)의
///   키가 된다 (PLAN §9) — 프로세스 간 안정성이 필요해 Hasher가 아닌 SHA-256.
public struct DocumentOutline: Equatable, Sendable {

    /// 헤딩과 다음 헤딩 사이의 연속 본문 한 덩어리.
    /// 헤딩 없는 문서(저널의 보통 모습)는 전체가 씬 하나(서두, level 0)다.
    public struct Scene: Equatable, Sendable {
        /// 이 씬을 여는 헤딩 레벨 (1–3). 0이면 문서 서두(첫 헤딩 이전).
        public let level: Int
        /// 뿌리부터 이 씬까지의 헤딩 제목 경로 — 예: ["1부", "3장", "밤"].
        /// 레벨을 건너뛴 헤딩(`#` 다음 바로 `###`)은 중간이 빈 문자열로 채워진다.
        public let headingPath: [String]
        /// 본문 내 위치(UTF-16, 여는 헤딩 줄 포함) — 에디터 커서(NSString 좌표)와
        /// 같은 단위라 변환 없이 비교할 수 있다.
        public let utf16Range: Range<Int>
        /// 씬 원문 SHA-256 앞 16자 — "같은 입력 재처리 금지"의 키 (CLAUDE.md §4).
        public let contentHash: String
    }

    /// 담화 순서의 씬들 — 이 배열 인덱스가 Pos v1이다 (PLAN §5).
    public let scenes: [Scene]

    /// 본문을 씬 배열로 파싱한다. 문서 전체를 한 번 훑는 O(n) —
    /// 30만 자 장편도 밀리초 단위라 편집 직후 백그라운드에서 부담 없이 돈다.
    public static func parse(_ body: String) -> DocumentOutline {
        var scenes: [Scene] = []
        /// 현재 헤딩 경로 스택 (레벨 1…3).
        var stack: [String] = []
        var sceneLevel = 0
        var scenePath: [String] = []
        var sceneStartUTF16 = 0
        var sceneStartIndex = body.startIndex

        /// 진행 중 씬을 닫아 배열에 붙인다. 헤딩 이전 서두가 공백뿐이면 버린다 —
        /// 빈 서두 씬은 앵커로서 의미가 없다.
        func closeScene(endUTF16: Int, endIndex: String.Index) {
            guard endUTF16 > sceneStartUTF16 else { return }
            let text = body[sceneStartIndex..<endIndex]
            if sceneLevel == 0,
                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return
            }
            scenes.append(
                Scene(
                    level: sceneLevel,
                    headingPath: scenePath,
                    utf16Range: sceneStartUTF16..<endUTF16,
                    contentHash: hash(text)
                ))
        }

        var lineStart = body.startIndex
        var utf16Pos = 0
        while lineStart < body.endIndex {
            let lineEnd =
                body[lineStart...].firstIndex(of: "\n")
                .map { body.index(after: $0) } ?? body.endIndex
            let line = body[lineStart..<lineEnd]
            if let (level, title) = headingLine(line) {
                closeScene(endUTF16: utf16Pos, endIndex: lineStart)
                // 경로 갱신 — 상위 레벨은 유지, 같은/하위 레벨은 잘라내고 대체.
                if stack.count >= level {
                    stack.removeSubrange((level - 1)...)
                }
                while stack.count < level - 1 { stack.append("") }
                stack.append(title)
                sceneLevel = level
                scenePath = stack
                sceneStartUTF16 = utf16Pos
                sceneStartIndex = lineStart
            }
            utf16Pos += line.utf16.count
            lineStart = lineEnd
        }
        closeScene(endUTF16: utf16Pos, endIndex: body.endIndex)
        return DocumentOutline(scenes: scenes)
    }

    /// 커서(UTF-16)가 속한 씬 인덱스. 씬이 없거나 커서가 첫 씬 앞이면 nil.
    public func sceneIndex(at utf16Offset: Int) -> Int? {
        scenes.lastIndex(where: { $0.utf16Range.lowerBound <= utf16Offset })
    }

    /// 커서 이전(커서가 속한 씬 포함) 씬들 — 커서 위치 **이후**의 지식을
    /// 프롬프트에 주입하지 않기 위한 시점 차단 질의 (CLAUDE.md §2-4).
    public func scenes(upTo utf16Offset: Int) -> ArraySlice<Scene> {
        guard let index = sceneIndex(at: utf16Offset) else { return scenes[..<0] }
        return scenes[...index]
    }

    /// `#{1,3} 제목` 꼴이면 (레벨, 제목). `####` 이상·공백 없는 `#텍스트`는 본문.
    /// 에디터의 제목 파생(`EntryStore.derivedTitle`)과 같은 판정 기준이다.
    private static func headingLine(_ line: Substring) -> (Int, String)? {
        var level = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", level < 4 {
            level += 1
            index = line.index(after: index)
        }
        guard (1...3).contains(level), index < line.endIndex, line[index] == " "
        else { return nil }
        let title = line[line.index(after: index)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (level, title)
    }

    private static func hash(_ text: Substring) -> String {
        SHA256.hash(data: Data(text.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
