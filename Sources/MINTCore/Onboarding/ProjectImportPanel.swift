import AppKit

struct ProjectFolderSelection {
    let directory: URL
    let legacyMode: WritingMode
}

@MainActor
enum ProjectImportPanel {
    static func select() -> ProjectFolderSelection? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "가져오기"
        panel.message = "프로젝트 폴더 또는 이전 MINT 저장 폴더를 선택하세요. 원본은 보존됩니다."
        guard panel.runModal() == .OK, let directory = panel.url else { return nil }
        let scoped = directory.startAccessingSecurityScopedResource()
        defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
        if ImportProjectCoordinator.containsProjectManifest(in: directory) {
            return ProjectFolderSelection(directory: directory, legacyMode: .general)
        }
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("entries.json").path) else {
            let alert = NSAlert()
            alert.messageText = "MINT 원고가 있는 폴더를 선택하세요"
            alert.informativeText = "project.json 또는 entries.json이 들어 있는 폴더를 선택해주세요."
            alert.runModal()
            return nil
        }
        let alert = NSAlert()
        alert.messageText = "가져올 프로젝트 종류"
        alert.informativeText = "원고에 맞는 작업 공간을 선택하세요."
        alert.addButton(withTitle: "Fiction")
        alert.addButton(withTitle: "General")
        alert.addButton(withTitle: "취소")
        let response = alert.runModal()
        guard response != .alertThirdButtonReturn else { return nil }
        return ProjectFolderSelection(directory: directory,
            legacyMode: response == .alertFirstButtonReturn ? .fiction : .general)
    }
}
