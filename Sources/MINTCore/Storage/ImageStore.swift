import AppKit

/// 저널에 붙인 이미지의 파일 저장·로드 (에디터 v3.1).
///
/// - 원본 데이터는 `~/Documents/MINT/images/<uuid>.<ext>`에 복사한다. 저장
///   마크다운에는 `![](images/<uuid>.<ext>)`처럼 **MINT 폴더 기준 상대경로**만
///   남겨, MINT 폴더를 통째로 옮겨도 참조가 깨지지 않는다.
/// - 렌더 이미지는 경로별로 캐시한다 (편집·드로잉 모두 메인 스레드).
///
/// 저장 위치 규칙은 `EntryStore.storageDirectory()`와 같은 `~/Documents/MINT/`를
/// 공유한다 — 여기서 다시 계산하는 이유는 파일 관심사를 분리하기 위해서다.
/// 캐시의 "메인 전용" 불변식은 주석이 아니라 격리로 강제한다 (이슈 #45) —
/// 호출부(BlockTextView·EpubExporter.export·테스트)는 모두 MainActor 맥락이다.
@MainActor
public enum MintImageStore {
    /// 지원 이미지 확장자 (붙여넣기·드롭·파일 선택 공통 필터).
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "webp", "bmp",
    ]

    private static var cache: [String: NSImage] = [:]

    /// 테스트 전용 저장소 격리 — 기본값 nil(실제 `~/Documents/MINT`).
    /// 회귀 테스트가 사용자 원고·asset을 건드리지 않게 한다 (이슈 #7).
    private static var directoryOverride: URL?

    public static func setDirectoryOverride(_ url: URL?) {
        directoryOverride = url
        cache.removeAll()
    }

    /// `~/Documents/MINT/` — 없으면 만든다.
    private static func mintDirectory() -> URL {
        if let override = directoryOverride { return override }
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("MINT", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `~/Documents/MINT/images/` — 없으면 만든다.
    private static func imagesDirectory() -> URL {
        let dir = mintDirectory().appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 이미지 데이터를 images 폴더에 복사하고 상대경로("images/<uuid>.<ext>")를 돌려준다.
    /// 실패하면 nil. 저장된 asset은 장부에 후보 등록 — 삽입이 취소돼도 유예 후
    /// 참조 기반으로 정리된다 (이슈 #17).
    public static func save(_ data: Data, ext rawExt: String) -> String? {
        let ext = normalizedExtension(rawExt)
        let name = "\(UUID().uuidString).\(ext)"
        let url = imagesDirectory().appendingPathComponent(name, isDirectory: false)
        do {
            try data.write(to: url, options: .atomic)
            let relative = "images/\(name)"
            AssetJanitor.record(relative)
            return relative
        } catch {
            return nil
        }
    }

    /// 상대경로(또는 절대경로)를 MINT 폴더 기준 파일 URL로 해석한다.
    /// 테스트 격리(directoryOverride)를 존중한다 — 앱·테스트의 정상 통로.
    public static func url(for relativePath: String) -> URL {
        if relativePath.hasPrefix("/") {
            return URL(fileURLWithPath: relativePath)
        }
        return mintDirectory().appendingPathComponent(relativePath, isDirectory: false)
    }

    /// 격리 밖 해석기 — 오버라이드 없는 기본 위치만 계산하는 순수 함수.
    /// **백그라운드 내보내기(EpubExporter) 전용** (#33): 메인 hop 없이 자산
    /// 후보 위치를 알아야 하기 때문이다. 테스트가 자산을 심는 경로는 반드시
    /// MainActor `url(for:)`/`resolveAssetURLs`를 거친다 — 이 함수는 폴백일 뿐.
    public nonisolated static func resolveURL(for relativePath: String) -> URL {
        if relativePath.hasPrefix("/") {
            return URL(fileURLWithPath: relativePath)
        }
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("MINT", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: false)
    }

    /// 상대경로의 이미지를 로드한다 (경로별 캐시). 없거나 못 읽으면 nil.
    /// 원격·차단 소스는 로컬 파일로 오해하지 않고 nil — 완전 로컬 원칙 (이슈 #12).
    public static func image(for relativePath: String) -> NSImage? {
        switch ImageReferenceParser.classify(relativePath) {
        case .managedRelative, .externalFile: break
        case .remote, .blocked: return nil
        }
        if let hit = cache[relativePath] { return hit }
        let fileURL = url(for: relativePath)
        guard let image = NSImage(contentsOf: fileURL), image.size.width > 0 else {
            return nil
        }
        if cache.count > 128 { cache.removeAll() }  // 폭주 방지 — 단순 전체 비움
        cache[relativePath] = image
        return image
    }

    // MARK: - 고아 정리는 금지 (이슈 #7)

    /// 과거 `pruneUnreferenced(keeping:)`는 정규식 하나로 "참조 중"을 판정해
    /// 나머지를 **영구 삭제**했다. title·angle destination·괄호·reference 문법을
    /// 못 읽어 실제 참조 중인 파일을 지웠고(이슈 #7 재현), 다른 저널 삭제만으로
    /// 표지 이미지가 사라질 수 있었다. 파서와 같은 참조 모델(#12)과 휴지통/지연
    /// GC(#17)가 준비될 때까지 **어떤 자동 삭제도 하지 않는다** — 고아 파일은
    /// 디스크 몇 KB의 비용이지만, 오삭제는 원고 일부의 영구 손실이다 (AGENTS §1).

    private static func normalizedExtension(_ ext: String) -> String {
        let lowered = ext.lowercased()
        guard imageExtensions.contains(lowered) else { return "png" }
        return lowered == "jpeg" ? "jpg" : lowered
    }
}
