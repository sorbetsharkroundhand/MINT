import AppKit
import SwiftMath

// MARK: - LaTeX renderer (SwiftMath)

/// Renders and caches LaTeX images on the main actor alongside editor updates and drawing (#45).
@MainActor
enum MathRenderer {
    /// Byte-bounded LRU eviction avoids clearing the entire cache during math-heavy typing (#53).
    private static var cache = ImageLRU(budgetBytes: mathCacheBudgetBytes)
    nonisolated private static let mathCacheBudgetBytes = 64 * 1024 * 1024

    /// Tests can exercise eviction with a smaller byte budget (#53).
    static func _testResetCache(budgetBytes: Int? = nil) {
        cache = ImageLRU(budgetBytes: budgetBytes ?? Self.mathCacheBudgetBytes)
    }

    /// Returns nil for invalid LaTeX so the editor can retain its source text.
    /// Display blocks use `.display`; inline atoms use `.text` (#20).
    static func image(
        latex: String, color: NSColor, fontSize: CGFloat,
        labelMode: MTMathUILabelMode = .display
    ) -> NSImage? {
        render(latex: latex, color: color, fontSize: fontSize, labelMode: labelMode).image
    }

    /// Returns an image or a parsing error for the editor to display (#22).
    static func render(
        latex: String, color: NSColor, fontSize: CGFloat,
        labelMode: MTMathUILabelMode = .display
    ) -> (image: NSImage?, error: String?) {
        let key = "\(labelMode == .display ? "D" : "T")|\(fontSize)|\(color.description)|\(latex)"
        if let hit = cache.find(key) { return (hit, nil) }
        let renderer = MTMathImage(
            latex: latex, fontSize: fontSize, textColor: color, labelMode: labelMode)
        let (error, image) = renderer.asImage()
        guard error == nil, let image, image.size.width > 0 else {
            return (nil, error?.localizedDescription ?? "수식을 해석하지 못했어요")
        }
        // Estimate RGBA storage with a 2x allowance for LRU accounting.
        let bytes = max(1, Int(image.size.width) * Int(image.size.height) * 4 * 2)
        cache.insert(key: key, image: image, bytes: bytes)
        return (image, nil)
    }

    /// Draws the error and original LaTeX with a dashed red outline distinct from valid math (#22).
    static func failurePlaceholder(
        message: String, latex: String, color: NSColor
    ) -> NSImage {
        let width = max(260, min(560, CGFloat(latex.count) * fontSize0 * 0.42))
        let height: CGFloat = 58
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        defer { image.unlockFocus() }

        let box = NSRect(x: 1, y: 1, width: width - 2, height: height - 2)
        let rounded = NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8)
        NSColor.systemRed.withAlphaComponent(0.06).setFill()
        rounded.fill()
        let dashed: [CGFloat] = [4, 4]
        NSColor.systemRed.withAlphaComponent(0.55).setStroke()
        rounded.setLineDash(dashed, count: 2, phase: 0)
        rounded.lineWidth = 1.5
        rounded.stroke()

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "⚠︎  수식을 해석하지 못했어요", attributes: [
            .font: MintFonts.ui(12, weight: .semibold),
            .foregroundColor: color,
        ]))
        text.append(NSAttributedString(string: "\n\(message)", attributes: [
            .font: MintFonts.ui(10.5),
            .foregroundColor: NSColor.systemRed.withAlphaComponent(0.9),
        ]))
        let trimmedLatex = latex.replacingOccurrences(of: "\n", with: " ⏎ ")
        text.append(NSAttributedString(string: "\n\(trimmedLatex)", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: color.withAlphaComponent(0.75),
        ]))
        let bounds = text.boundingRect(
            with: NSSize(width: width - 24, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin])
        text.draw(with: NSRect(
            x: 12, y: (height - bounds.height) / 2,
            width: width - 24, height: bounds.height),
            options: [.usesLineFragmentOrigin])
        return image
    }

    /// Converts a rendered image to PDF data for the copy action (#22).
    static func pdfData(from image: NSImage) -> Data? {
        var box = CGRect(origin: .zero, size: image.size)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return nil }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        image.draw(in: box)
        NSGraphicsContext.restoreGraphicsState()
        context.closePDF()
        return data as Data
    }

    private static let fontSize0: CGFloat = 14
}
