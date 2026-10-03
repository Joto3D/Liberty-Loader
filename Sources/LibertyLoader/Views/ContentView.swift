import LibertyCore
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: String, CaseIterable, Identifiable {
    case play = "Play"
    case mods = "Mods"
    case performance = "Performance"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .play: return "play.circle.fill"
        case .mods: return "shippingbox.fill"
        case .performance: return "speedometer"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .play

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch selection ?? .play {
            case .play: PlayView()
            case .mods: ModsView()
            case .performance: PerformanceView()
            case .settings: SettingsView()
            }
        }
        .fileImporter(
            isPresented: $model.showImporter,
            allowedContentTypes: [.zip, .folder, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.install(urls) }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// Small transient banner used by several screens.
@MainActor
struct StatusBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.statusMessage {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(message)
                Spacer()
                Button { model.statusMessage = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }
            .padding(10)
            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
