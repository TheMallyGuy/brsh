import SwiftUI

@main
struct brshApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FFlagServer.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                FFlagServer.shared.endBackground()
                FFlagServer.shared.restart()
            case .background:
                FFlagServer.shared.enteredBackground()
            default:
                break
            }
        }
    }
}
