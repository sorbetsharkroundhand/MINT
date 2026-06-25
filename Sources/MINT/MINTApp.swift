import SwiftUI

/// MINT — Mac INtelligent note Taker
/// 온디바이스 한글 자동완성 저널 에디터의 진입점.
@main
struct MINTApp: App {
    var body: some Scene {
        WindowGroup("MINT") {
            ContentView()
        }
        .defaultSize(width: 760, height: 580)
    }
}
