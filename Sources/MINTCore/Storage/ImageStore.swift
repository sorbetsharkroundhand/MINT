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
public enum MintImageStore {
    /// 지원 이미지 확장자 (붙여넣기·드롭·파일 선택 공통 필터).
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "webp", "bmp",
    ]

    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]

    /// `~/Documents/MINT/` — 없으면 만든다.
    private static func mintDirectory() -> URL {
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
    /// 실패하면 nil.
    public static func save(_ data: Data, ext rawExt: String) -> String? {
        let ext = normalizedExtension(rawExt)
        let name = "\(UUID().uuidString).\(ext)"
        let url = imagesDirectory().appendingPathComponent(name, isDirectory: false)
        do {
            try data.write(to: url, options: .atomic)
            return "images/\(name)"
        } catch {
            return nil
        }
    }

    /// 상대경로(또는 절대경로)를 MINT 폴더 기준 파일 URL로 해석한다.
    public static func url(for relativePath: String) -> URL {
        if relativePath.hasPrefix("/") {
            return URL(fileURLWithPath: relativePath)
        }
        return mintDirectory().appendingPathComponent(relativePath, isDirectory: false)
    }

    /// 상대경로의 이미지를 로드한다 (경로별 캐시). 없거나 못 읽으면 nil.
    public static func image(for relativePath: String) -> NSImage? {
        if let hit = cache[relativePath] { return hit }
        let fileURL = url(for: relativePath)
        guard let image = NSImage(contentsOf: fileURL), image.size.width > 0 else {
            return nil
        }
        if cache.count > 128 { cache.removeAll() }  // 폭주 방지 — 단순 전체 비움
        cache[relativePath] = image
        return image
    }

    private static func normalizedExtension(_ ext: String) -> String {
        let lowered = ext.lowercased()
        guard imageExtensions.contains(lowered) else { return "png" }
        return lowered == "jpeg" ? "jpg" : lowered
    }
}
