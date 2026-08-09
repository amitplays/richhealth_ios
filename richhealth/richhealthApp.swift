import SwiftUI

@main struct richhealthApp: App {
    @State private var appEnv = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnv)
        }
    }
}
