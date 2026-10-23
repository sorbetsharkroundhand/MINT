import AppKit

enum WorkspacePouchEdge: String, Codable { case left, right, top, bottom }

/// Presentation geometry only. Neither the label nor its tools participate in
/// tile sizing, row spacing, scrolling extent, or the native editor's layout.
struct WorkspacePouchPlacement: Equatable {
    let frame: CGRect
    let index: CGRect
    let tools: CGRect
    let bodyTop: CGFloat

    init?(object: CGRect, visible: CGRect, tile: WorkspaceTileID, toolHeight: CGFloat) {
        guard visible.intersects(CGRect(x: object.minX, y: object.minY, width: object.width, height: 32)) else { return nil }
        bodyTop = min(6, max(0, object.minY - visible.minY))
        let width = WorkspacePouchMetrics.indexWidth(for: tile, available: object.width)
        index = CGRect(x: object.width - width - 36, y: bodyTop + 2, width: width, height: 28)
        let available = max(0, visible.maxY - object.minY - 32)
        tools = CGRect(x: 0, y: bodyTop + 32, width: object.width, height: min(toolHeight, available))
        frame = CGRect(x: object.minX, y: object.minY - bodyTop, width: object.width,
            height: max(object.height + bodyTop, tools.maxY))
    }

    /// One perimeter for the entire object, with a small organic rise in its
    /// own top edge. There is no separate tab outline or attachment skirt.
    var contour: CGPath {
        let w = frame.width, h = frame.height, r: CGFloat = 13
        let left = max(r + 6, index.minX - 4), right = min(w - r - 6, index.maxX + 4)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r, y: bodyTop))
        path.addLine(to: CGPoint(x: left - 6, y: bodyTop))
        path.addCurve(to: CGPoint(x: left + 6, y: 0), control1: CGPoint(x: left, y: bodyTop), control2: CGPoint(x: left, y: 0))
        path.addLine(to: CGPoint(x: right - 6, y: 0))
        path.addCurve(to: CGPoint(x: right + 6, y: bodyTop), control1: CGPoint(x: right, y: 0), control2: CGPoint(x: right, y: bodyTop))
        path.addLine(to: CGPoint(x: w - r, y: bodyTop))
        path.addQuadCurve(to: CGPoint(x: w, y: bodyTop + r), control: CGPoint(x: w, y: bodyTop))
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: r, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: bodyTop + r))
        path.addQuadCurve(to: CGPoint(x: r, y: bodyTop), control: CGPoint(x: 0, y: bodyTop))
        path.closeSubpath()
        return path
    }
}

/// The object's shared silhouette is below its persistent native host. Controls
/// are above it; pointer events outside those controls still reach the editor.
final class WorkspacePouchSurfaceView: NSView {
    var placement: WorkspacePouchPlacement? { didSet { if placement != oldValue { needsDisplay = true } } }
    var color = NSColor.clear { didSet { if color != oldValue { needsDisplay = true } } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let placement, let context = NSGraphicsContext.current?.cgContext else { return }
        color.setFill(); context.addPath(placement.contour); context.fillPath()
    }
}

enum WorkspacePouchGeometry {
    static func dockedFrame(window: CGRect, edge: WorkspacePouchEdge, ratio: Double) -> CGRect {
        let horizontal = edge == .top || edge == .bottom
        let size = horizontal ? CGSize(width: 236, height: 38) : CGSize(width: 38, height: 236)
        let ratio = min(0.95, max(0.05, ratio.isFinite ? ratio : 0.45))
        let availableWidth = max(40, window.width - size.width - 16)
        let availableHeight = max(40, window.height - 36 - size.height - 16)
        let x: CGFloat, y: CGFloat
        switch edge {
        case .left: x = window.minX + 8; y = window.maxY - 44 - size.height - availableHeight * ratio
        case .right: x = window.maxX - size.width - 8; y = window.maxY - 44 - size.height - availableHeight * ratio
        case .top: x = window.minX + 8 + availableWidth * ratio; y = window.maxY - 44 - size.height
        case .bottom: x = window.minX + 8 + availableWidth * ratio; y = window.minY + 8
        }
        return CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size)
    }
    static func nearestEdge(point: CGPoint, window: CGRect) -> WorkspacePouchEdge {
        let distances: [(WorkspacePouchEdge, CGFloat)] = [(.left, abs(point.x - window.minX)),
            (.right, abs(window.maxX - point.x)), (.top, abs(window.maxY - 36 - point.y)),
            (.bottom, abs(point.y - window.minY))]
        return distances.min { $0.1 < $1.1 }!.0
    }
    static func clampOrb(_ origin: CGPoint, screen: CGRect, margin: CGFloat = 12) -> CGPoint {
        CGPoint(x: min(screen.maxX - 44 - margin, max(screen.minX + margin, origin.x)),
                y: min(screen.maxY - 44 - margin, max(screen.minY + margin, origin.y)))
    }
}

struct WorkspaceSpringPoint {
    var position: CGPoint
    var velocity = CGVector.zero
    mutating func step(target: CGPoint, stiffness: CGFloat, damping: CGFloat, elapsed: TimeInterval) {
        let dt = CGFloat(min(0.030, max(0.004, elapsed)))
        velocity.dx += ((target.x - position.x) * stiffness - velocity.dx * damping) * dt
        velocity.dy += ((target.y - position.y) * stiffness - velocity.dy * damping) * dt
        position.x += velocity.dx * dt; position.y += velocity.dy * dt
    }
    func isSettled(at target: CGPoint) -> Bool {
        hypot(position.x - target.x, position.y - target.y) < 0.15 && hypot(velocity.dx, velocity.dy) < 0.8
    }
}
