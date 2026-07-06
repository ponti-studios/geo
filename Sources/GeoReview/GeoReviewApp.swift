import AppKit
import SwiftUI

@main
struct GeoReviewApp: App {
    @StateObject private var store: ReviewStore

    init() {
        let config: ReviewAppConfig
        do {
            config = try ReviewAppConfig.load()
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        GeoReviewLogger.log("Geo Review app initialized")
        _store = StateObject(wrappedValue: ReviewStore(dbPath: config.dbPath))
    }

    var body: some Scene {
        WindowGroup("Geo Review") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1320, minHeight: 820)
        }
        .defaultSize(width: 1480, height: 920)
    }
}
