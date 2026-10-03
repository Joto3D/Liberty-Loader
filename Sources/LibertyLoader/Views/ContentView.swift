import LibertyCore
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: String, CaseIterable, Identifiable {
    case play, mods, browse, performance, settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .play: return "Play"
        case .mods: return "Mods"
        case .browse: return "Browse"
        case .performance: return "Performance"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .play: return "play.fill"
        case .mods: return "shippingbox.fill"
        case .browse: return "sparkle.magnifyingglass"
        case .performance: return "speedometer"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem = .play

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                switch selection {
                case .play: PlayView(selection: $selection)
                case .mods: ModsView()
                case .browse: BrowseView(selection: $selection)
                case .performance: PerformanceView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hdBackground)
        }
        .preferredColorScheme(.dark)
        .tint(.hdYellow)
        .toolbarBackground(Color.hdBackground, for: .windowToolbar)
        .fileImporter(
            isPresented: $model.showImporter,
            allowedContentTypes: [.zip, .folder, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.install(urls) }
        }
        .sheet(isPresented: $model.showSetup) {
            SetupWizardView().environment(model)
        }
        .task { model.showSetupIfNeeded() }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
    }
}

@MainActor
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem
    @State private var hovered: SidebarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logo
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)

            VStack(spacing: 4) {
                ForEach(SidebarItem.allCases) { item in
                    navButton(item)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            footer
                .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.hdBackground)
    }

    private var logo: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(Color.hdYellow)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "LIBERTY")
                        .font(.hdDisplay(20))
                        .foregroundStyle(Color.hdText)
                    Text(verbatim: "LOADER")
                        .font(.hdDisplay(20))
                        .foregroundStyle(Color.hdYellow)
                }
            }
            HazardStripe(stripeWidth: 6)
                .frame(height: 5)
                .clipShape(Rectangle())
        }
    }

    private func navButton(_ item: SidebarItem) -> some View {
        let isSelected = selection == item
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selection = item }
        } label: {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(isSelected ? Color.hdYellow : Color.clear)
                    .frame(width: 3, height: 20)
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                Spacer()
                if item == .mods, model.mods.contains(where: \.hasUpdate) {
                    Circle().fill(Color.hdInfo).frame(width: 7, height: 7)
                }
                if item == .play, model.availableUpdate != nil {
                    Circle().fill(Color.hdInfo).frame(width: 7, height: 7)
                }
            }
            .foregroundStyle(isSelected ? Color.hdYellow : Color.hdText.opacity(hovered == item ? 1 : 0.75))
            .padding(.vertical, 9)
            .padding(.trailing, 10)
            .background(
                isSelected ? Color.hdYellow.opacity(0.10) : Color.white.opacity(hovered == item ? 0.04 : 0),
                in: RoundedRectangle(cornerRadius: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? item : (hovered == item ? nil : hovered) }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isGameRunning {
                StatusPill(color: .hdSuccess, text: "Deployed")
            } else if model.crossOver == nil || model.game == nil {
                StatusPill(color: .hdDanger, text: "Setup needed")
            } else {
                StatusPill(color: .hdYellow, text: "Ready")
            }
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(verbatim: PlaytimeRecord.format(model.playtime.total()))
            }
            .font(.hdLabel(11))
            .foregroundStyle(Color.hdMuted)
        }
    }
}

/// Transient confirmation shown at the top of pages.
@MainActor
struct StatusBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.statusMessage {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.hdSuccess)
                Text(verbatim: message).foregroundStyle(Color.hdText)
                Spacer()
                Button { withAnimation { model.statusMessage = nil } } label: {
                    Image(systemName: "xmark").foregroundStyle(Color.hdMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.hdSuccess.opacity(0.10), in: CutCornerShape(cut: 8))
            .overlay(CutCornerShape(cut: 8).stroke(Color.hdSuccess.opacity(0.35), lineWidth: 1))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
