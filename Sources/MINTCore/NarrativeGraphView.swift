import SwiftUI

// Narrative Graph UI (요구사항 §22–§26) — Git branch graph의 시각 문법을 소설의
// 인물 서사에 옮긴 스토리라인 그래프.
//
// 핵심 모델: **인물 = 지속 가능한 graph lane**. 색상 태그가 아니라 화면을 위에서
// 아래로 읽는 동안 계속 흐르는 선이다. Git 문법과의 대응:
// - continuous lane = 인물의 서사 흐름 (첫 사건에서 열리고 마지막 사건에서 닫힘)
// - commit node     = 사건 (참여 인물의 레인 위)
// - merge/junction  = 여러 인물이 함께 얽히는 사건 — 참여 레인들이 한 점으로 합류
// - branch          = 공유 사건 뒤 각자의 레인으로 재분리
//
// 데이터는 전부 KnowledgeSnapshot의 파생물(canonicalEvents·characters·flows·
// causalLinks)이다 — UI 전용 데이터 모델을 따로 만들지 않는다 (요구사항 §37).

// MARK: - 레이아웃 엔진 (요구사항 §25)

/// 스토리라인 배치 — 결정적. 행 = 정본 사건(담화 순서), 레인 = 인물.
///
/// 배치 원칙:
/// - 레인은 그 인물의 첫 사건 행에서 열리고 마지막 사건 행에서 닫힌다 —
///   화면 구간에 실제로 활동하는 인물만 폭을 차지한다 (active characters).
/// - 레인 순서는 git처럼 고정하지 않는다. 합류 사건마다 참여 레인을 현재
///   중앙값 위치의 인접 블록으로 재배열해 교차를 줄인다 (storyline 그리디).
/// - 닫힌 레인의 자리는 즉시 회수돼 뒤 레인이 왼쪽으로 당겨진다.
/// - 같은 입력이면 항상 같은 배치 — 사건 순서·participants 순서만 쓴다.
struct NarrativeGraphLayout {
    struct Lane: Identifiable {
        var id: String
        var characterID: UUID?
        var name: String
        /// 색 시드 — 인물 흐름 persistent ID의 해시 (재분석 후에도 같은 색,
        /// 요구사항 §24). nil = 서술 레인(참여자 없는 사건)으로 액센트색.
        var colorSeed: Int?
        /// 이 레인이 노드를 갖는 행들.
        var eventRows: [Int]
    }

    struct Node: Identifiable {
        var event: CanonicalEvent
        var row: Int
        /// 노드 x — 레인폭 단위. 합류 노드는 참여 블록의 중앙 (소수 가능).
        var x: CGFloat
        /// 참여 레인 id들 — 합류 판정·강조·hover의 근거.
        var laneIDs: [String]
        var isJunction: Bool { laneIDs.count >= 2 }
        var id: String { event.canonicalKey }
    }

    var lanes: [Lane]
    var nodes: [Node]
    /// 레인 id → 활동 구간 매 행의 (행, x) 표본 — 이 폴리라인이 곧 레인 선.
    var points: [String: [(row: Int, x: CGFloat)]]
    /// 동시 활성 레인 최대 수 — 그래프 최소 폭의 근거.
    var laneSlotCount: Int

    static let narratorLaneID = "lane-narrator"

    static func compute(snapshot: KnowledgeSnapshot) -> NarrativeGraphLayout {
        let events = snapshot.canonicalEvents
        let known = Set(snapshot.characters.map(\.id))
        let nameByID = Dictionary(
            uniqueKeysWithValues: snapshot.characters.map { ($0.id, $0.name) })
        // 인물 흐름의 colorSeed를 우선 쓰고, 흐름이 아직 없는 인물(사건 1개)은
        // 같은 persistent ID 규칙으로 시드를 만든다 — 흐름 생성 전후 색이 같다.
        let seedByCharacter = Dictionary(
            uniqueKeysWithValues: snapshot.flows
                .filter { $0.kind == .character }
                .compactMap { flow in flow.characterID.map { ($0, flow.colorSeed) } })

        func laneID(_ cid: UUID) -> String { "lane-chr-\(cid.uuidString)" }

        // 행별 참여 레인 — 참여자가 없으면 서술 레인 (등장 순서 유지, 중복 제거).
        var characterByLane: [String: UUID] = [:]
        let rowLanes: [[String]] = events.map { event in
            var seen = Set<String>()
            let ids = event.participants.filter { known.contains($0) }.compactMap {
                cid -> String? in
                let lid = laneID(cid)
                characterByLane[lid] = cid
                return seen.insert(lid).inserted ? lid : nil
            }
            return ids.isEmpty ? [narratorLaneID] : ids
        }

        // 레인 활동 구간 (첫 사건 행 ... 마지막 사건 행).
        var rowsByLane: [String: [Int]] = [:]
        for (row, lids) in rowLanes.enumerated() {
            for lid in lids { rowsByLane[lid, default: []].append(row) }
        }

        var order: [String] = []
        var appearance: [String] = []
        var points: [String: [(row: Int, x: CGFloat)]] = [:]
        var nodes: [Node] = []
        var slots = 0

        for (row, event) in events.enumerated() {
            let lids = rowLanes[row]

            // 활성화 — 인물의 첫 사건 행에서 레인이 열린다.
            for lid in lids where !order.contains(lid) {
                order.append(lid)
                appearance.append(lid)
            }

            // 합류 그룹핑 — 참여 레인을 현재 중앙값 위치의 인접 블록으로 옮긴다.
            // 상대 순서는 보존한다 (불필요한 교차를 만들지 않는다).
            if lids.count >= 2 {
                let block = lids.sorted {
                    order.firstIndex(of: $0)! < order.firstIndex(of: $1)!
                }
                let indices = block.map { order.firstIndex(of: $0)! }
                let target = indices[indices.count / 2]
                let removedBefore = indices.filter { $0 < target }.count
                order.removeAll { block.contains($0) }
                order.insert(
                    contentsOf: block,
                    at: min(max(0, target - removedBefore), order.count))
            }
            slots = max(slots, order.count)

            // 이번 행의 모든 활성 레인 위치 기록 — 행 사이 변화가 곧 곡선이다.
            for (i, lid) in order.enumerated() {
                points[lid, default: []].append((row, CGFloat(i)))
            }

            // 노드 x — 합류면 참여 레인들을 블록 중앙의 한 점으로 모은다.
            let nodeX: CGFloat
            if lids.count >= 2 {
                let idxs = lids.map { CGFloat(order.firstIndex(of: $0)!) }
                nodeX = idxs.reduce(0, +) / CGFloat(idxs.count)
                for lid in lids {
                    points[lid]![points[lid]!.count - 1].x = nodeX
                }
            } else {
                nodeX = CGFloat(order.firstIndex(of: lids[0])!)
            }
            nodes.append(Node(event: event, row: row, x: nodeX, laneIDs: lids))

            // 비활성화 — 마지막 사건 행을 지나면 레인을 닫고 자리를 회수한다.
            order.removeAll { rowsByLane[$0]?.last == row }
        }

        let lanes: [Lane] = appearance.map { lid in
            if lid == narratorLaneID {
                return Lane(
                    id: lid, characterID: nil, name: "서술", colorSeed: nil,
                    eventRows: rowsByLane[lid] ?? [])
            }
            let cid = characterByLane[lid]!
            let seed = seedByCharacter[cid]
                ?? NarrativeFlow(
                    id: "flow-chr-\(cid.uuidString)", kind: .character, name: ""
                ).colorSeed
            return Lane(
                id: lid, characterID: cid, name: nameByID[cid] ?? "?",
                colorSeed: seed, eventRows: rowsByLane[lid] ?? [])
        }

        return NarrativeGraphLayout(
            lanes: lanes, nodes: nodes, points: points, laneSlotCount: max(slots, 1))
    }
}

// MARK: - 레인 색 (요구사항 §24)

/// 인물 persistent ID 기반 안정 색 — 재분석·재실행 후에도 같은 인물은 같은 색.
/// 깃 그래프 시각 문법에 맞춘 선명한 8색 (형광 금지, 라이트/다크 두 벌).
enum FlowPalette {
    /// (라이트, 다크) 짝 — 레인이 겹쳐도 한눈에 갈리는 대비 순서.
    static let hues: [(light: UInt32, dark: UInt32)] = [
        (0x2F80D0, 0x5AA7F0),  // 청
        (0xD9930D, 0xF0B429),  // 호박
        (0xC2255C, 0xEC5F94),  // 자홍
        (0x6741D9, 0x9775FA),  // 보라
        (0x099268, 0x2FCB9B),  // 청록
        (0xD9480F, 0xFF8B4D),  // 주황
        (0x3B5BDB, 0x7B95FF),  // 남
        (0x5C940D, 0x94D82D),  // 연두
    ]

    /// seed nil = 서술 레인 — 앱 액센트색.
    static func color(seed: Int?, theme: MintTheme, dark: Bool) -> Color {
        guard let seed else { return theme.novelC }
        let pair = hues[seed % hues.count]
        return Color(nsColor: NSColor(hex: dark ? pair.dark : pair.light))
    }
}

// MARK: - 그래프 뷰

struct NarrativeGraphView: View {
    @ObservedObject var indexer: BackgroundIndexer
    @ObservedObject var store: EntryStore
    let theme: MintTheme
    var embedded = false

    @Environment(\.colorScheme) private var colorScheme

    /// 선택된 인물 레인 — 그 인물의 전체 경로와 junction을 강조 (요구사항 §24·§26).
    @State private var selectedLaneID: String?
    /// hover 중인 사건 — 참여 인물 전원의 경로를 강조.
    @State private var hoveredEventKey: String?
    /// 선택된 노드 — 상세 패널 (요구사항 §23·§26).
    @State private var selectedEventKey: String?
    /// 필터 (요구사항 §25).
    @State private var filter: GraphFilter = .all

    enum GraphFilter: String, CaseIterable {
        case all = "전체"
        case currentScene = "현재 씬"
    }

    private let rowHeight: CGFloat = 36
    private let laneWidth: CGFloat = 20
    private let leftInset: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if let snapshot = liveSnapshot, !snapshot.canonicalEvents.isEmpty {
                let layout = NarrativeGraphLayout.compute(snapshot: snapshot)
                legend(layout)
                if !snapshot.chronoConflicts.isEmpty {
                    conflictNotice(snapshot)
                }
                GeometryReader { geo in
                    ScrollView {
                        graphBody(layout, snapshot: snapshot, width: geo.size.width)
                            .padding(.vertical, 4)
                    }
                }
                if let key = selectedEventKey,
                    let event = snapshot.canonicalEvents.first(where: { $0.canonicalKey == key })
                {
                    Divider()
                    EventDetailPanel(
                        event: event, snapshot: snapshot, theme: theme,
                        onJump: { jump(query: $0) },
                        onClose: { selectedEventKey = nil })
                }
            } else {
                placeholder
                if embedded { Spacer(minLength: 0) }
            }
        }
        .padding(14)
        .frame(width: embedded ? nil : 480)
    }

    private var liveSnapshot: KnowledgeSnapshot? {
        guard let snapshot = indexer.snapshot,
            snapshot.entryID == store.activeEntry?.id
        else { return nil }
        return snapshot
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 11))
                .foregroundStyle(theme.novelC)
            Text("서사 그래프")
                .font(MintFonts.uiFont(13, .semibold))
                .foregroundStyle(theme.inkC)
            Spacer()
            Picker("", selection: $filter) {
                ForEach(GraphFilter.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .frame(width: 120)
            ManualIndexButton(indexer: indexer, theme: theme)
        }
    }

    private var placeholder: some View {
        Text(
            store.activeEntry?.resolvedKind == .novel
                ? "사건이 아직 없어요. 인물을 등록하고 「지금 읽기」를 누르면 사건 그래프가 만들어져요."
                : "소설 종류의 문서에서만 그래프를 만들어요."
        )
        .font(MintFonts.uiFont(11))
        .foregroundStyle(theme.ink3C)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    /// 인물 범례 — 클릭 = 그 인물의 서사 경로 강조 (요구사항 §24 "색상만으로
    /// 구분하지 마라": 레인·라벨·선택 상태가 함께 인물을 식별한다).
    private func legend(_ layout: NarrativeGraphLayout) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(layout.lanes) { lane in
                    let color = FlowPalette.color(
                        seed: lane.colorSeed, theme: theme, dark: colorScheme == .dark)
                    Button {
                        selectedLaneID = selectedLaneID == lane.id ? nil : lane.id
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(color).frame(width: 7, height: 7)
                            Text(lane.name)
                                .font(MintFonts.uiFont(10, .medium))
                                .foregroundStyle(
                                    selectedLaneID == lane.id ? theme.inkC : theme.ink2C)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(
                                selectedLaneID == lane.id
                                    ? color.opacity(0.18) : theme.chipC))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("클릭: 이 인물의 서사 경로와 만남(junction) 강조")
                }
            }
        }
    }

    /// 시간 관계 모순 표시 (요구사항 §29) — 임의 확정 대신 Conflict 상태.
    private func conflictNotice(_ snapshot: KnowledgeSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(theme.novelC)
            Text("시간 관계가 서로 모순되는 간선 \(snapshot.chronoConflicts.count)개 — 사건 상세에서 시간 관계를 직접 고칠 수 있어요.")
                .font(MintFonts.uiFont(10))
                .foregroundStyle(theme.ink2C)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 본체 — Canvas(레인 선) + 노드 + 인라인 라벨

    @ViewBuilder
    private func graphBody(
        _ layout: NarrativeGraphLayout, snapshot: KnowledgeSnapshot, width: CGFloat
    ) -> some View {
        let visible = visibleNodes(layout, snapshot: snapshot)
        let height = CGFloat(max(visible.count, 1)) * rowHeight
        // 표시 행 재배열 — 필터로 숨은 행을 접는다.
        let rowRemap = Dictionary(
            uniqueKeysWithValues: visible.enumerated().map { ($0.element.row, $0.offset) })
        let emphasized = emphasizedLanes(visible: visible)

        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                drawLanes(
                    context: &context, layout: layout, visible: visible,
                    rowRemap: rowRemap, emphasized: emphasized)
            }
            .frame(width: width, height: height)

            ForEach(visible) { node in
                let displayRow = rowRemap[node.row] ?? 0
                let labelX = leftInset + node.x * laneWidth + 16

                nodeView(node, layout: layout, emphasized: emphasized)
                    .position(
                        x: leftInset + node.x * laneWidth,
                        y: (CGFloat(displayRow) + 0.5) * rowHeight)

                // 사건 텍스트는 노드 바로 오른쪽 — 레인 깊이만큼만 들여쓴다.
                nodeLabel(node, snapshot: snapshot, emphasized: emphasized)
                    .frame(
                        width: max(60, width - labelX - 4), height: rowHeight,
                        alignment: .leading)
                    .offset(x: labelX, y: CGFloat(displayRow) * rowHeight)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    /// 강조할 레인 집합 — hover(사건 참여자 전원) > 인물 선택 > 없음(nil).
    private func emphasizedLanes(visible: [NarrativeGraphLayout.Node]) -> Set<String>? {
        if let hovered = hoveredEventKey,
            let node = visible.first(where: { $0.id == hovered })
        {
            return Set(node.laneIDs)
        }
        if let selected = selectedLaneID { return [selected] }
        return nil
    }

    private func visibleNodes(
        _ layout: NarrativeGraphLayout, snapshot: KnowledgeSnapshot
    ) -> [NarrativeGraphLayout.Node] {
        switch filter {
        case .all:
            return layout.nodes
        case .currentScene:
            guard let caret = indexer.caretProvider?() ?? nil,
                let sceneIndex = snapshot.outline.sceneIndex(at: caret)
            else { return layout.nodes }
            let hash = snapshot.outline.scenes[sceneIndex].contentHash
            // 현재 씬의 사건 + 그와 인과로 이어진 사건.
            let sceneKeys = Set(layout.nodes.filter { $0.event.sceneHash == hash }.map(\.id))
            let related = Set(
                snapshot.causalLinks
                    .filter { sceneKeys.contains($0.fromKey) || sceneKeys.contains($0.toKey) }
                    .flatMap { [$0.fromKey, $0.toKey] })
            return layout.nodes.filter {
                sceneKeys.contains($0.id) || related.contains($0.id)
            }
        }
    }

    /// 레인 선 그리기 — 인물별 폴리라인. 행 사이 x 변화는 S-곡선으로 잇는다
    /// (합류·분기·교차가 전부 이 곡선이다, 요구사항 §22).
    private func drawLanes(
        context: inout GraphicsContext, layout: NarrativeGraphLayout,
        visible: [NarrativeGraphLayout.Node], rowRemap: [Int: Int],
        emphasized: Set<String>?
    ) {
        let dark = colorScheme == .dark

        for lane in layout.lanes {
            guard let pts = layout.points[lane.id] else { continue }
            // 필터로 숨은 행은 건너뛰고 남은 표본끼리 잇는다.
            let visiblePts: [CGPoint] = pts.compactMap { p in
                rowRemap[p.row].map {
                    CGPoint(
                        x: leftInset + p.x * laneWidth,
                        y: (CGFloat($0) + 0.5) * rowHeight)
                }
            }
            guard visiblePts.count >= 2 else { continue }

            let color = FlowPalette.color(seed: lane.colorSeed, theme: theme, dark: dark)
            let isEmphasized = emphasized?.contains(lane.id) ?? false
            let dimmed = emphasized != nil && !isEmphasized
            let stroke = color.opacity(dimmed ? 0.12 : (isEmphasized ? 1 : 0.85))
            let width: CGFloat = isEmphasized ? 3 : 2.2

            var line = Path()
            line.move(to: visiblePts[0])
            for (prev, next) in zip(visiblePts, visiblePts.dropFirst()) {
                if abs(prev.x - next.x) < 0.5 {
                    line.addLine(to: next)
                } else {
                    let midY = (prev.y + next.y) / 2
                    line.addCurve(
                        to: next,
                        control1: CGPoint(x: prev.x, y: midY),
                        control2: CGPoint(x: next.x, y: midY))
                }
            }
            context.stroke(
                line, with: .color(stroke),
                style: StrokeStyle(lineWidth: width, lineCap: .round))
        }

        // 인과 간선 — 레인 선과 구분되는 점선 (요구사항 §6·§23). 선택 노드
        // 관련만 그린다 — 전부 그리면 소음이다.
        if let selected = selectedEventKey {
            let nodeByKey = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
            let related = (liveSnapshot?.causalLinks ?? []).filter {
                $0.fromKey == selected || $0.toKey == selected
            }
            for link in related {
                guard let from = nodeByKey[link.fromKey], let to = nodeByKey[link.toKey]
                else { continue }
                let a = CGPoint(
                    x: leftInset + from.x * laneWidth,
                    y: (CGFloat(rowRemap[from.row] ?? 0) + 0.5) * rowHeight)
                let b = CGPoint(
                    x: leftInset + to.x * laneWidth,
                    y: (CGFloat(rowRemap[to.row] ?? 0) + 0.5) * rowHeight)
                var dash = Path()
                dash.move(to: a)
                let midY = (a.y + b.y) / 2
                dash.addCurve(
                    to: b,
                    control1: CGPoint(x: a.x - laneWidth * 0.7, y: midY),
                    control2: CGPoint(x: b.x - laneWidth * 0.7, y: midY))
                context.stroke(
                    dash, with: .color(theme.novelC.opacity(0.55)),
                    style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
            }
        }

        // 노드 헤일로 — 노드 자리의 선을 지워 배경이 비치는 틈을 만든다.
        // 합류점엔 여러 색의 선이 모이므로 전 노드에 틈이 있어야 읽힌다.
        context.blendMode = .destinationOut
        for node in visible {
            let center = CGPoint(
                x: leftInset + node.x * laneWidth,
                y: (CGFloat(rowRemap[node.row] ?? 0) + 0.5) * rowHeight)
            let diameter = node.isJunction ? junctionOuterSize(node.event) : dotSize(node.event)
            let radius = diameter / 2 + 1.5
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: center.x - radius, y: center.y - radius,
                        width: radius * 2, height: radius * 2)),
                with: .color(.black))
        }
        context.blendMode = .normal
    }

    /// 노드 지름 — 중요도 기반 (요구사항 §23).
    private func dotSize(_ event: CanonicalEvent) -> CGFloat {
        event.importance >= 5 ? 12 : event.importance >= 4 ? 10 : 8
    }

    /// 합류(junction) 노드의 바깥 지름.
    private func junctionOuterSize(_ event: CanonicalEvent) -> CGFloat {
        dotSize(event) + 6
    }

    /// 사건 노드 — 단독 사건은 인물색 채움 원, 합류 사건은 링+중심점(◉).
    /// 여러 인물이 얽히는 사건을 깃 그래프의 병합 노드 문법으로 표시한다 (§23).
    @ViewBuilder
    private func nodeView(
        _ node: NarrativeGraphLayout.Node, layout: NarrativeGraphLayout,
        emphasized: Set<String>?
    ) -> some View {
        let dark = colorScheme == .dark
        let laneByID = Dictionary(uniqueKeysWithValues: layout.lanes.map { ($0.id, $0) })
        let color: Color =
            node.isJunction
            ? theme.novelC
            : FlowPalette.color(
                seed: node.laneIDs.first.flatMap { laneByID[$0]?.colorSeed },
                theme: theme, dark: dark)
        let dimmed = emphasized != nil && Set(node.laneIDs).isDisjoint(with: emphasized!)
        let opacity: Double = dimmed ? 0.2 : 1
        let size = dotSize(node.event)

        Button {
            selectedEventKey = selectedEventKey == node.id ? nil : node.id
        } label: {
            ZStack {
                if node.isJunction {
                    let outer = junctionOuterSize(node.event)
                    Circle()
                        .strokeBorder(color.opacity(opacity), lineWidth: 2.2)
                        .frame(width: outer, height: outer)
                    Circle()
                        .fill(color.opacity(opacity))
                        .frame(width: size * 0.45, height: size * 0.45)
                } else {
                    Circle()
                        .fill(color.opacity(opacity))
                        .frame(width: size, height: size)
                }
                if selectedEventKey == node.id {
                    Circle()
                        .strokeBorder(theme.inkC.opacity(0.6), lineWidth: 1.5)
                        .frame(width: size + 12, height: size + 12)
                }
            }
            .contentShape(Circle().scale(2))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredEventKey = node.id
            } else if hoveredEventKey == node.id {
                hoveredEventKey = nil
            }
        }
        .help(node.event.summary)
    }

    /// 사건 라벨 — 노드 바로 오른쪽. 클릭 = 상세, hover = 참여 경로 강조.
    @ViewBuilder
    private func nodeLabel(
        _ node: NarrativeGraphLayout.Node, snapshot: KnowledgeSnapshot,
        emphasized: Set<String>?
    ) -> some View {
        let dimmed = emphasized != nil && Set(node.laneIDs).isDisjoint(with: emphasized!)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text(node.event.summary)
                    .font(MintFonts.uiFont(10.5, node.event.importance >= 4 ? .semibold : .regular))
                    .foregroundStyle(dimmed ? theme.ink3C : theme.inkC)
                    .lineLimit(1)
                if node.event.perspectives.count >= 2 {
                    Text("관점 \(node.event.perspectives.count)")
                        .font(MintFonts.uiFont(8.5))
                        .foregroundStyle(theme.novelC)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(theme.novelBgC))
                }
            }
            // 시간 순위가 담화 순서와 다르면 표시 — "실제로 언제 일어난 사건인가".
            if let rank = snapshot.chronoRank(of: node.id), rank != node.row {
                Text("시간순 \(rank + 1)번째")
                    .font(MintFonts.uiFont(8.5))
                    .foregroundStyle(theme.ink3C)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedEventKey = selectedEventKey == node.id ? nil : node.id }
        .onHover { hovering in
            if hovering {
                hoveredEventKey = node.id
            } else if hoveredEventKey == node.id {
                hoveredEventKey = nil
            }
        }
    }

    private func jump(query: String) {
        let resolved = store.activeEntry.flatMap {
            SourceAnchor.resilientQuery(for: query, in: $0.body)
        } ?? query
        store.requestSearchJump(store.activeID, query: resolved)
    }
}

// MARK: - 사건 상세 패널 (요구사항 §23·§26)

private struct EventDetailPanel: View {
    let event: CanonicalEvent
    let snapshot: KnowledgeSnapshot
    let theme: MintTheme
    var onJump: (String) -> Void
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(event.summary)
                        .font(MintFonts.uiFont(11.5, .semibold))
                        .foregroundStyle(theme.inkC)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.ink3C)
                    }
                    .buttonStyle(.plain)
                }

                // 참여 인물·흐름.
                let names = Dictionary(
                    uniqueKeysWithValues: snapshot.characters.map { ($0.id, $0.name) })
                let who = event.participants.compactMap { names[$0] }
                if !who.isEmpty {
                    detailLine("인물", who.joined(separator: " · "))
                }
                let flowNames = snapshot.flows
                    .filter { $0.eventKeys.contains(event.canonicalKey) }
                    .map(\.name)
                if !flowNames.isEmpty {
                    detailLine("흐름", flowNames.joined(separator: " · "))
                }
                if let rank = snapshot.chronoRank(of: event.canonicalKey) {
                    detailLine("시간", "시간순 \(rank + 1)번째 (본문 등장과 별개)")
                }

                // 관점들 (요구사항 §12·§13) — 서로 모순될 수 있는 서술을 나란히.
                if event.perspectives.count >= 2 {
                    Text("관점")
                        .font(MintFonts.uiFont(10, .semibold))
                        .foregroundStyle(theme.ink2C)
                    ForEach(event.perspectives) { perspective in
                        Button {
                            if let quote = perspective.quote { onJump(quote) }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(perspective.viewpoint ?? "서술")
                                    .font(MintFonts.uiFont(9, .semibold))
                                    .foregroundStyle(theme.novelC)
                                Text(perspective.summary)
                                    .font(MintFonts.uiFont(10))
                                    .foregroundStyle(theme.ink2C)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(perspective.source.rawValue)·\(perspective.reliability.rawValue)")
                                    .font(MintFonts.uiFont(8.5))
                                    .foregroundStyle(theme.ink3C)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("이 관점의 원문 보기")
                    }
                }

                // 인과 (요구사항 §6·§26) — 원인·결과를 클릭해 따라간다.
                let causes = snapshot.causes(of: event.canonicalKey)
                let effects = snapshot.effects(of: event.canonicalKey)
                ForEach(causes) { link in
                    causalRow(link, label: "← \(link.kind.rawValue)", otherKey: link.fromKey)
                }
                ForEach(effects) { link in
                    causalRow(link, label: "→ \(link.kind.rawValue)", otherKey: link.toKey)
                }

                // 근거 원문 (요구사항 §23 Source Evidence).
                if let quote = event.quote {
                    Button {
                        onJump(quote)
                    } label: {
                        Label("근거 원문 보기 — “\(quote)”", systemImage: "text.quote")
                            .font(MintFonts.uiFont(10))
                            .foregroundStyle(theme.blueC)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 180)
    }

    @ViewBuilder private func detailLine(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(key)
                .font(MintFonts.uiFont(9.5, .semibold))
                .foregroundStyle(theme.ink3C)
            Text(value)
                .font(MintFonts.uiFont(10))
                .foregroundStyle(theme.ink2C)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func causalRow(
        _ link: CausalLink, label: String, otherKey: String
    ) -> some View {
        if let other = snapshot.canonicalEvent(for: otherKey) {
            Button {
                if let quote = other.quote { onJump(quote) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(label)
                        .font(MintFonts.uiFont(9, .semibold))
                        .foregroundStyle(theme.novelC)
                    Text(other.summary)
                        .font(MintFonts.uiFont(10))
                        .foregroundStyle(theme.ink2C)
                        .lineLimit(2)
                    if !link.reason.isEmpty {
                        Text(link.reason)
                            .font(MintFonts.uiFont(8.5))
                            .foregroundStyle(theme.ink3C)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("연결된 사건의 원문 보기")
        }
    }
}
