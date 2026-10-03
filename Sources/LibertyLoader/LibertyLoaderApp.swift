import SwiftUI

@main
struct LibertyLoaderApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Liberty Loader") {
            ContentView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 560)
                .task { model.refresh() }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Install Mod…") { model.showImporter = true }
                    .keyboardShortcut("o")
            }
        }
    }
}
