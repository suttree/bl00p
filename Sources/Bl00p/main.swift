// Linux entry point. SwiftOpenUI apps are launched by handing the App type to
// a backend rather than through the `@main` attribute, so this file is the
// module's top-level code. It is excluded from the macOS target, which uses
// `Platform/MacEntry.swift`.

import Foundation
import SwiftOpenUI
import BackendGTK4

struct Bl00pApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 980, minHeight: 640)
        }
    }
}

GTK4Backend().run(Bl00pApp.self)
