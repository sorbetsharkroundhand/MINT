import Foundation
import CryptoKit

struct WorkspaceCommandItem: Identifiable {
    enum Kind: String { case command = "명령", file = "문서", character = "인물", source = "원문" }
    enum Action {
        case typewriter, focus, openAll, theme, document(WritingDocumentID)
        case character(WritingDocumentID, UUID), source(OriginalSourceReference)
    }
    let id: String
    let title: String
    let detail: String
    let kind: Kind
    let action: Action
}

enum WorkspaceCommandSearch {
    static func items(in project: WritingProject, query: String, typewriter: Bool, focus: Bool) -> [WorkspaceCommandItem] {
        var items: [WorkspaceCommandItem] = [
            .init(id: "typewriter", title: "타자기 모드 \(typewriter ? "끄기" : "켜기")", detail: "현재 문단을 화면 가운데로", kind: .command, action: .typewriter),
            .init(id: "focus", title: "집중 모드 \(focus ? "끄기" : "켜기")", detail: "현재 문단에 집중", kind: .command, action: .focus),
            .init(id: "all", title: "모든 문서 나란히 열기", detail: "열린 원고 유지", kind: .command, action: .openAll),
            .init(id: "theme", title: "테마 전환", detail: "밝게 / 어둡게", kind: .command, action: .theme)
        ]
        let documents = project.documents.filter { !project.trashedDocumentIDs.contains($0.id) }
        for document in documents {
            items.append(.init(id: "file.\(document.id)", title: document.title, detail: "나란히 열기", kind: .file, action: .document(document.id)))
        }
        var seen: Set<UUID> = []
        for document in documents {
            if let data = try? WriterDocumentData.decode(project.userData[WriterDocumentData.key(for: document.id)], documentID: document.id) {
                for card in data.characters where !card.name.isEmpty && card.autoRegistered != true && seen.insert(card.id).inserted {
                    items.append(.init(id: "character.\(card.id)", title: card.name, detail: card.note, kind: .character, action: .character(document.id, card.id)))
                }
            }
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Original offsets are constructed from the original, never from rendered or trimmed text.
        for document in documents {
            let body = document.body as NSString
            var cursor = 0
            let revision = SHA256.hash(data: Data(document.body.utf8)).map { String(format: "%02x", $0) }.joined()
            while cursor < body.length {
                let paragraph = body.paragraphRange(for: NSRange(location: cursor, length: 0))
                cursor = paragraph.upperBound
                let raw = body.substring(with: paragraph)
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                if !needle.isEmpty && !raw.localizedCaseInsensitiveContains(needle) && !document.title.localizedCaseInsensitiveContains(needle) && !WorkspaceCommandItem.Kind.source.rawValue.localizedCaseInsensitiveContains(needle) { continue }
                var start = paragraph.location
                if !needle.isEmpty {
                    let match = body.range(of: needle, options: .caseInsensitive, range: paragraph)
                    if match.location != NSNotFound { start = max(paragraph.location, match.location - 100) }
                }
                let chunk = body.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: min(1024, paragraph.upperBound - start)))
                let quote = body.substring(with: chunk)
                let reference = OriginalSourceReference(key: .init(projectID: project.id, documentID: document.id), revision: revision,
                    evidence: .init(documentID: document.id, quote: quote, utf16Hint: chunk.location), selection: .passage)
                items.append(.init(id: "source.\(document.id).\(start)", title: String(quote.prefix(100)).replacingOccurrences(of: "\n", with: " "),
                    detail: document.title, kind: .source, action: .source(reference)))
                if needle.isEmpty || items.filter({ $0.kind == .source }).count >= 9 { break }
            }
        }
        return Array(items.lazy.filter { needle.isEmpty || ($0.title + " " + $0.detail + " " + $0.kind.rawValue).localizedCaseInsensitiveContains(needle) }.prefix(9))
    }
}
