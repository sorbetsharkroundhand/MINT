import AppKit
import Darwin

// Keep the original clipboard only in memory. The UI smoke stops this helper
// immediately after Paste; failure cleanup also sends SIGTERM to restore it.
let board = NSPasteboard.general
let saved = (board.pasteboardItems ?? []).map { original in
    let item = NSPasteboardItem()
    for type in original.types {
        if let data = original.data(forType: type) { item.setData(data, forType: type) }
    }
    return item
}
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.bitmapData!.initialize(repeating: 0xCC, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
let png = bitmap.representation(using: .png, properties: [:])!
var ownedChange = 0
let signals = [SIGTERM, SIGINT].map { value in
    signal(value, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: value, queue: .main)
    source.setEventHandler {
        // A clipboard copied by the user while the test ran takes precedence.
        if board.changeCount == ownedChange {
            board.clearContents()
            if !saved.isEmpty { board.writeObjects(saved) }
        }
        exit(0)
    }
    source.resume()
    return source
}
board.clearContents()
board.setData(png, forType: .png)
ownedChange = board.changeCount
do {
    try Data("ready".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    board.clearContents()
    if !saved.isEmpty { board.writeObjects(saved) }
    exit(1)
}
dispatchMain()
