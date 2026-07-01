import Foundation
import SwiftUI

/// 저널 본문을 로컬 마크다운 파일에 보관하는 스토어(M1).
///
/// - 저장 위치: `~/Documents/MINT/journal.md` (PLAN §1 "로컬 마크다운" 결정)
/// - 시작 시 `load()`로 기존 내용 복원.
/// - `text` 변경 시 짧은 디바운스 후 autosave — 매 키 입력마다 디스크에
///   쓰지 않도록 이전 저장 작업을 취소하고 다시 예약한다.
///
/// MVP는 단일 문서(§1 "단일 에디터")이므로 파일 하나만 다룬다.
@MainActor
public final class DocumentStore: ObservableObject {
    /// 에디터가 양방향 바인딩하는 본문.
    @Published public var text: String = ""

    /// autosave까지 기다리는 시간(초). 입력이 멈춘 뒤에만 쓴다.
    private let autosaveDelay: Duration
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    public init(autosaveDelay: Duration = .milliseconds(800)) {
        self.autosaveDelay = autosaveDelay
        self.fileURL = Self.defaultFileURL()
    }

    /// `~/Documents/MINT/journal.md` 경로. 디렉터리가 없으면 만든다.
    private static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("MINT", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("journal.md", isDirectory: false)
    }

    /// 디스크에서 기존 저널을 읽어 `text`를 채운다. 파일이 없으면 빈 상태로 시작.
    public func load() {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        text = contents
    }

    /// 디바운스 autosave 예약. `text`가 바뀔 때마다 호출한다(예: `.onChange`).
    public func scheduleSave() {
        saveTask?.cancel()
        let snapshot = text
        saveTask = Task { [autosaveDelay, fileURL] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            try? snapshot.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
