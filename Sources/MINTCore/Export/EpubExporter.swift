import AppKit
import UniformTypeIdentifiers

/// 소설을 EPUB 3으로 내보낸다 (요구 7 — 파일 메뉴·사이드바 문맥 메뉴).
///
/// 외부 의존성 없이 최소 규격만 직접 조립한다:
/// - `mimetype`(무압축·첫 항목) + `META-INF/container.xml` + `OEBPS/`(opf·nav·css·본문)
/// - 본문 마크다운은 단순 변환기로 XHTML이 된다 — `# `(제목 1)마다 챕터를 나눠
///   목차(nav)와 spine에 올린다. 소설 본문(문단·제목·인용·목록·이미지) 중심이고,
///   수식·코드는 고정폭 소스로 남는다.
/// - 압축은 시스템 `/usr/bin/zip` — mimetype은 규격상 무압축(-0) 첫 항목이어야
///   해서 두 번에 나눠 담는다.
public enum EpubExporter {

    public enum ExportError: LocalizedError {
        case zipFailed(String)

        public var errorDescription: String? {
            switch self {
            case .zipFailed(let message):
                return "EPUB 압축에 실패했어요 — \(message)"
            }
        }
    }

    // MARK: - 진입점

    /// 저장 패널을 띄워 내보낸다 — 파일 메뉴와 사이드바 문맥 메뉴가 공유한다.
    @MainActor
    public static func exportWithPanel(_ entry: JournalEntry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .zip]
        panel.nameFieldStringValue = sanitizedFileName(entry.title) + ".epub"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // 설정의 저자 이름은 값 스냅샷으로만 넘긴다 (CLAUDE.md §4 격리 경계).
            try export(entry, to: url, author: CompletionSettings.shared.authorName)
        } catch {
            let alert = NSAlert()
            alert.messageText = "EPUB 내보내기 실패"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    /// 저널 한 편을 EPUB 파일로 만든다. UI 없이 파일만 쓴다.
    /// `author`는 설정의 저자 이름(필명) — 비어 있으면 저자 메타데이터를 생략한다.
    @MainActor
    public static func export(
        _ entry: JournalEntry, to destination: URL, author: String = ""
    ) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("mint-epub-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        let metaInf = staging.appendingPathComponent("META-INF", isDirectory: true)
        let oebps = staging.appendingPathComponent("OEBPS", isDirectory: true)
        try fm.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try fm.createDirectory(at: oebps, withIntermediateDirectories: true)

        // mimetype — 개행 없이. zip의 첫 항목으로 무압축 저장돼야 리더가 알아본다.
        try Data("application/epub+zip".utf8)
            .write(to: staging.appendingPathComponent("mimetype"))
        try containerXML.write(
            to: metaInf.appendingPathComponent("container.xml"),
            atomically: true, encoding: .utf8)

        var images: [String] = []
        let chapters = makeChapters(from: entry, copyingImagesInto: oebps, collected: &images)
        for (index, chapter) in chapters.enumerated() {
            try chapterXHTML(chapter).write(
                to: oebps.appendingPathComponent(chapterFile(index)),
                atomically: true, encoding: .utf8)
        }
        try styleCSS.write(
            to: oebps.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        try navXHTML(bookTitle: entry.title, chapters: chapters).write(
            to: oebps.appendingPathComponent("nav.xhtml"), atomically: true, encoding: .utf8)
        try packageOPF(entry: entry, chapters: chapters, images: images, author: author).write(
            to: oebps.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        try runZip(["-X", "-0", "book.epub", "mimetype"], in: staging)
        try runZip(["-rX", "book.epub", "META-INF", "OEBPS"], in: staging)

        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: staging.appendingPathComponent("book.epub"), to: destination)
    }

    // MARK: - 마크다운 → 챕터 XHTML

    struct Chapter {
        var title: String
        var html: String
    }

    /// 본문을 `# ` 제목마다 챕터로 나누고, 각 챕터를 XHTML 조각으로 변환한다.
    /// 이미지(`![](images/…)`)는 OEBPS/images/로 복사해 참조를 살린다.
    /// export(@MainActor)에서만 호출된다 — 이미지 URL 해석이 MintImageStore(메인
    /// 격리)를 거치므로 같은 격리를 따른다 (이슈 #45).
    @MainActor private static func makeChapters(
        from entry: JournalEntry, copyingImagesInto oebps: URL, collected images: inout [String]
    ) -> [Chapter] {
        var chapters: [Chapter] = []
        var title = plainTitle(entry.title)
        var html = ""
        // 첫 h1 앞에 본문이 없으면 그 "빈 서문 챕터"는 만들지 않는다.
        var started = false
        var inCode = false
        var listTag: String?

        func closeList() {
            if let tag = listTag {
                html += "</\(tag)>\n"
                listTag = nil
            }
        }
        func openList(_ tag: String) {
            if listTag != tag {
                closeList()
                html += "<\(tag)>\n"
                listTag = tag
            }
        }

        for rawLine in entry.body.components(separatedBy: "\n") {
            var line = rawLine
            if line.trimmingCharacters(in: .whitespaces) == "```" {
                closeList()
                inCode.toggle()
                html += inCode ? "<pre><code>" : "</code></pre>\n"
                continue
            }
            if inCode {
                html += escape(line) + "\n"
                continue
            }
            // 정렬 래퍼는 스타일로 옮긴다.
            var align: String?
            if let match = alignWrapper.firstMatch(
                in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                align = (line as NSString).substring(with: match.range(at: 1))
                line = (line as NSString).substring(with: match.range(at: 2))
            }

            if line.hasPrefix("# ") {
                closeList()
                if started || !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chapters.append(Chapter(title: title, html: html))
                }
                title = plainTitle(String(line.dropFirst(2)))
                html = ""
                started = true
            } else if line.hasPrefix("### ") {
                closeList()
                html += "<h3>\(inline(String(line.dropFirst(4))))</h3>\n"
            } else if line.hasPrefix("## ") {
                closeList()
                html += "<h2>\(inline(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
                openList("ul")
                let mark = line.hasPrefix("- [x] ") ? "☑" : "☐"
                html += "<li>\(mark) \(inline(String(line.dropFirst(6))))</li>\n"
            } else if line.hasPrefix("> ") || line == ">" {
                closeList()
                let quoted = line == ">" ? "" : String(line.dropFirst(2))
                html += "<blockquote><p>\(inline(quoted))</p></blockquote>\n"
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                openList("ul")
                html += "<li>\(inline(String(line.dropFirst(2))))</li>\n"
            } else if let match = line.range(of: #"^(\d+)\.\s"#, options: .regularExpression) {
                openList("ol")
                html += "<li>\(inline(String(line[match.upperBound...])))</li>\n"
            } else if line.range(of: #"^---+\s*$"#, options: .regularExpression) != nil {
                closeList()
                html += "<hr/>\n"
            } else if line.hasPrefix("$$"), line.hasSuffix("$$"), line.count >= 4 {
                closeList()
                let source = String(line.dropFirst(2).dropLast(2))
                html += "<p class=\"math\"><code>\(escape(source))</code></p>\n"
            } else if let attrs = BlockTextView.imageAttrs(
                from: line.trimmingCharacters(in: .whitespaces)) {
                closeList()
                if let relative = copyImage(attrs.src, into: oebps) {
                    if !images.contains(relative) { images.append(relative) }
                    html += "<p class=\"image\"><img src=\"\(relative)\" alt=\"\"/></p>\n"
                }
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                closeList()
            } else {
                closeList()
                let style = align.map { " style=\"text-align:\($0)\"" } ?? ""
                html += "<p\(style)>\(inline(line))</p>\n"
            }
        }
        closeList()
        chapters.append(Chapter(title: title, html: html))
        return chapters
    }

    /// 원본 이미지를 OEBPS/images/로 복사하고 EPUB 내 상대경로를 돌려준다.
    @MainActor private static func copyImage(_ src: String, into oebps: URL) -> String? {
        // 원격·차단 소스는 EPUB에 실을 로컬 asset이 아니다 — 파일로 오해해
        // 이상한 경로를 만들지 않는다 (이슈 #12). 누락 보고는 #15 몫.
        switch ImageReferenceParser.classify(src) {
        case .managedRelative, .externalFile: break
        case .remote, .blocked: return nil
        }
        let sourceURL = MintImageStore.url(for: src)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }
        let dir = oebps.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = sourceURL.lastPathComponent
        let dest = dir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: dest.path) {
            guard (try? FileManager.default.copyItem(at: sourceURL, to: dest)) != nil else {
                return nil
            }
        }
        return "images/\(name)"
    }

    // MARK: - 인라인 변환

    /// `&`·`<`·`>`만 이스케이프한다 — 따옴표를 남겨야 이스케이프 뒤에도
    /// `<font color="#…">` 태그를 알아볼 수 있다 (inline이 이어서 처리).
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// 인라인 마크다운(굵게·기울임·코드·`<font>` 색/크기)을 XHTML로 바꾼다.
    private static func inline(_ text: String) -> String {
        var s = escape(text)
        // <font color size> → span style (이스케이프된 형태를 매칭).
        let ns = s as NSString
        var result = ""
        var cursor = 0
        for match in fontTag.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(
                location: cursor, length: match.range.location - cursor))
            let attrs = ns.substring(with: match.range(at: 1))
            let content = ns.substring(with: match.range(at: 2))
            var styles: [String] = []
            if let color = firstGroup(fontColorAttr, in: attrs) {
                styles.append("color:#\(color)")
            }
            if let size = firstGroup(fontSizeAttr, in: attrs) {
                styles.append("font-size:\(size)px")
            }
            result += "<span style=\"\(styles.joined(separator: ";"))\">\(content)</span>"
            cursor = match.range.upperBound
        }
        result += ns.substring(from: cursor)
        s = result
        // 마커 → 태그. 순서 중요: *** > ** > *.
        s = boldItalic.stringByReplacingMatches(
            in: s, range: fullRange(s), withTemplate: "<strong><em>$1</em></strong>")
        s = bold.stringByReplacingMatches(
            in: s, range: fullRange(s), withTemplate: "<strong>$1</strong>")
        s = italic.stringByReplacingMatches(
            in: s, range: fullRange(s), withTemplate: "<em>$1</em>")
        s = codeSpan.stringByReplacingMatches(
            in: s, range: fullRange(s), withTemplate: "<code>$1</code>")
        return s
    }

    /// 제목용 — 마커·태그를 벗겨 순수 글자만 남긴다 (nav·opf에 들어간다).
    /// EntryStore의 태그 스트리퍼(MainActor)를 재사용한다.
    @MainActor
    private static func plainTitle(_ text: String) -> String {
        let stripped = EntryStore.strippedInlineTags(text)
            .replacingOccurrences(of: #"[*`]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? "제목 없음" : stripped
    }

    private static func fullRange(_ s: String) -> NSRange {
        NSRange(location: 0, length: (s as NSString).length)
    }

    private static func firstGroup(_ rx: NSRegularExpression, in text: String) -> String? {
        guard let match = rx.firstMatch(in: text, range: fullRange(text)) else { return nil }
        return (text as NSString).substring(with: match.range(at: 1))
    }

    private static let alignWrapper = try! NSRegularExpression(
        pattern: #"^<p align="(center|right)">(.*)</p>$"#)
    private static let fontTag = try! NSRegularExpression(
        pattern: #"&lt;font ([^&]*)&gt;(.*?)&lt;/font&gt;"#)
    private static let fontColorAttr = try! NSRegularExpression(
        pattern: ##"color="#([0-9A-Fa-f]{6})""##)
    private static let fontSizeAttr = try! NSRegularExpression(
        pattern: #"size="([0-9.]+)""#)
    private static let boldItalic = try! NSRegularExpression(
        pattern: #"(?<!\*)\*\*\*([^*\n]+)\*\*\*(?!\*)"#)
    private static let bold = try! NSRegularExpression(
        pattern: #"(?<!\*)\*\*([^*\n]+)\*\*(?!\*)"#)
    private static let italic = try! NSRegularExpression(
        pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#)
    private static let codeSpan = try! NSRegularExpression(
        pattern: #"`([^`\n]+)`"#)

    // MARK: - 패키지 문서들

    private static let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """

    /// 소설다운 기본 조판 — 세리프·넉넉한 행간·들여쓰기 없는 문단 간격.
    private static let styleCSS = """
        body { font-family: "Noto Serif KR", serif; line-height: 1.75; margin: 1em; }
        h1 { font-size: 1.5em; margin: 1.6em 0 1em; }
        h2 { font-size: 1.25em; margin: 1.4em 0 0.8em; }
        h3 { font-size: 1.1em; margin: 1.2em 0 0.6em; }
        p { margin: 0 0 0.75em; }
        blockquote { color: #666; border-left: 3px solid #999; margin: 1em 0; padding-left: 1em; }
        pre, code { font-family: ui-monospace, Menlo, monospace; font-size: 0.85em; }
        pre { background: #f2f2f2; padding: 0.8em; border-radius: 8px; overflow-x: auto; }
        hr { border: none; border-top: 1px solid #ccc; margin: 2em auto; width: 40%; }
        .math { text-align: center; margin: 1.2em 0; }
        .image { text-align: center; margin: 1.2em 0; }
        img { max-width: 100%; }
        """

    private static func chapterFile(_ index: Int) -> String { "chapter\(index).xhtml" }

    private static func chapterXHTML(_ chapter: Chapter) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="ko" lang="ko">
        <head>
          <title>\(escape(chapter.title))</title>
          <link rel="stylesheet" type="text/css" href="style.css"/>
        </head>
        <body>
          <section epub:type="chapter">
            <h1>\(escape(chapter.title))</h1>
        \(chapter.html)
          </section>
        </body>
        </html>
        """
    }

    private static func navXHTML(bookTitle: String, chapters: [Chapter]) -> String {
        let items = chapters.enumerated()
            .map { "      <li><a href=\"\(chapterFile($0.offset))\">\(escape($0.element.title))</a></li>" }
            .joined(separator: "\n")
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="ko" lang="ko">
            <head><title>\(escape(bookTitle))</title></head>
            <body>
              <nav epub:type="toc">
                <h1>목차</h1>
                <ol>
            \(items)
                </ol>
              </nav>
            </body>
            </html>
            """
    }

    /// OPF 패키지 문서. `private`가 아닌 이유는 저자 메타데이터를 zip 없이
    /// 단위 테스트로 고정하기 위해서다 (EpubMetadataTests).
    @MainActor
    static func packageOPF(
        entry: JournalEntry, chapters: [Chapter], images: [String], author: String = ""
    ) -> String {
        let modified: String = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter.string(from: .now)
        }()
        // 저자 이름이 비면 `<dc:creator>` 자체를 넣지 않는다 — 빈 저자명은
        // 리더 서가에 "이름 없음"으로 남아 없는 것만 못하다.
        let creatorXML: String = {
            let name = author.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return "" }
            return "\n    <dc:creator id=\"creator\">\(escape(name))</dc:creator>"
                + "\n    <meta refines=\"#creator\" property=\"role\""
                + " scheme=\"marc:relators\">aut</meta>"
        }()
        var manifest = [
            #"<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>"#,
            #"<item id="css" href="style.css" media-type="text/css"/>"#,
        ]
        var spine: [String] = []
        for index in chapters.indices {
            manifest.append(
                "<item id=\"ch\(index)\" href=\"\(chapterFile(index))\" media-type=\"application/xhtml+xml\"/>")
            spine.append("<itemref idref=\"ch\(index)\"/>")
        }
        for (index, image) in images.enumerated() {
            manifest.append(
                "<item id=\"img\(index)\" href=\"\(image)\" media-type=\"\(mediaType(of: image))\"/>")
        }
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id" xml:lang="ko">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="pub-id">urn:uuid:\(entry.id.uuidString.lowercased())</dc:identifier>
                <dc:title>\(escape(plainTitle(entry.title)))</dc:title>\(creatorXML)
                <dc:language>ko</dc:language>
                <meta property="dcterms:modified">\(modified)</meta>
              </metadata>
              <manifest>
                \(manifest.joined(separator: "\n    "))
              </manifest>
              <spine>
                \(spine.joined(separator: "\n    "))
              </spine>
            </package>
            """
    }

    private static func mediaType(of path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "tiff", "tif": "image/tiff"
        case "bmp": "image/bmp"
        default: "image/png"
        }
    }

    // MARK: - zip

    private static func runZip(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = arguments
        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            throw ExportError.zipFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "zip 종료 코드 \(process.terminationStatus)"
            throw ExportError.zipFailed(message)
        }
    }

    /// 파일 이름에 쓸 수 없는 문자를 정리한다 (AppCommands와 같은 규칙).
    private static func sanitizedFileName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "소설" : String(cleaned.prefix(60))
    }
}
