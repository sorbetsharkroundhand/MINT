import AppKit
import SwiftUI

/// 이미지 객체 선택 시 뜨는 툴바 액션 — `BlockTextView.performImage(_:)`이 처리한다.
enum ImageObjectAction {
    /// 가로 정렬 — "left" / "center" / "right".
    case align(String)
    /// 표시 너비(%) — 컬럼 폭 대비.
    case width(Int)
    /// 대체 텍스트(alt)와 마우스오버 제목 저장 (이슈 #14).
    case metadata(alt: String, title: String?)
    /// alt·title 편집 카드를 연다 — 저장은 `metadata`로 돌아온다.
    case editMetadata
    /// 깨진 이미지 복구 — 파일을 다시 골라 원래 참조 위치에 심는다 (이슈 #15).
    case locateFile
    /// 깨진 이미지의 원래 위치를 Finder에서 보여준다 (이슈 #15).
    case revealInFinder
    /// 이미지 뒤에 빈 줄을 넣고 커서를 옮긴다.
    case lineBreak
    /// 이미지 문단 삭제.
    case delete
}

/// 선택된 이미지 위에 뜨는 플로팅 툴바 (정렬·크기·줄바꿈·삭제).
/// 텍스트 서식 툴바(`SelectionToolbarView`)와 같은 리퀴드 글래스 톤.
struct ImageObjectToolbarView: View {
    let theme: MintTheme
    /// 현재 이미지 너비(%) — 표시용(크기 조절은 모서리 핸들 드래그).
    let width: Int
    let align: String
    /// 로드 실패 플레이스홀더인가 — 복구 액션(찾기·Finder)을 노출한다 (이슈 #15).
    var isPlaceholder: Bool = false
    let onAction: (ImageObjectAction) -> Void

    var body: some View {
        HStack(spacing: 2) {
            if isPlaceholder {
                iconButton("magnifyingglass", active: false, help: "파일 찾아 복구") {
                    onAction(.locateFile)
                }
                iconButton("folder", active: false, help: "Finder에서 보기") {
                    onAction(.revealInFinder)
                }
                divider
            }
            iconButton("arrow.left.to.line", active: align == "left", help: "왼쪽 정렬") {
                onAction(.align("left"))
            }
            iconButton(
                "arrow.left.and.right", active: align == "center", help: "가운데 정렬"
            ) { onAction(.align("center")) }
            iconButton("arrow.right.to.line", active: align == "right", help: "오른쪽 정렬") {
                onAction(.align("right"))
            }
            divider
            // 현재 너비 표시 — 조절은 이미지 오른쪽 아래 모서리 핸들을 드래그.
            Text("\(width)%")
                .font(MintFonts.monoUI(10, .semibold))
                .foregroundStyle(theme.ink2C)
                .frame(minWidth: 30)
                .help("크기 조절: 모서리 핸들 드래그")
            divider
            iconButton("text.below.photo", active: false, help: "대체 텍스트·제목 편집") {
                onAction(.editMetadata)
            }
            iconButton("return", active: false, help: "줄바꿈 (아래 새 줄)") {
                onAction(.lineBreak)
            }
            iconButton("trash", active: false, help: "이미지 삭제") {
                onAction(.delete)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(theme.pillC)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(theme.pillBorderC)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .fixedSize()
    }

    private var divider: some View {
        theme.sepStrongC.frame(width: 1, height: 15).padding(.horizontal, 3)
    }

    private func iconButton(
        _ systemName: String, active: Bool, help: String, action: @escaping () -> Void
    ) -> some View {
        ImageToolbarButton(theme: theme, active: active, help: help, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
        }
    }
}

/// alt·title 편집 카드 — 툴바 아래에 뜨는 작은 시트. Enter는 적용, Esc는 닫기.
/// 저장은 `ImageObjectAction.metadata`로 에디터에 돌아간다 (이슈 #14).
struct ImageAltEditorView: View {
    let theme: MintTheme
    let initialAlt: String
    let initialTitle: String?
    let onApply: (_ alt: String, _ title: String?) -> Void
    let onCancel: () -> Void
    @State private var alt: String = ""
    @State private var title: String = ""
    @FocusState private var focusedField: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("대체 텍스트 (VoiceOver·EPUB)")
                .font(MintFonts.uiFont(10, .semibold))
                .foregroundStyle(theme.ink2C)
            TextField("이 이미지를 말로 설명하면", text: $alt)
                .textFieldStyle(.roundedBorder)
                .font(MintFonts.uiFont(11))
                .focused($focusedField, equals: 0)
                .onSubmit { submit() }
            Text("마우스오버 제목 (선택)")
                .font(MintFonts.uiFont(10, .semibold))
                .foregroundStyle(theme.ink2C)
            TextField("비워 두면 title을 넣지 않는다", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(MintFonts.uiFont(11))
                .focused($focusedField, equals: 1)
                .onSubmit { submit() }
            HStack {
                Spacer()
                Button("취소") { onCancel() }
                    .controlSize(.small)
                Button("적용") { submit() }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(theme.pillC)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(theme.pillBorderC)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .onExitCommand { onCancel() }
        .onAppear {
            alt = initialAlt
            title = initialTitle ?? ""
            focusedField = 0
        }
    }

    private func submit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        onApply(
            alt.trimmingCharacters(in: .whitespacesAndNewlines),
            trimmedTitle.isEmpty ? nil : trimmedTitle)
    }
}

/// 이미지 툴바 공용 버튼 — hover/활성 배경.
private struct ImageToolbarButton<Label: View>: View {
    let theme: MintTheme
    let active: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(active ? theme.blueC : theme.inkC)
                .frame(height: 24)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? theme.activeBgC : (hovered ? theme.hoverC : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}
