import AppKit
import LibertyCore
import SwiftUI

enum BrowseTab: CaseIterable, Identifiable {
    case trending, latestAdded, latestUpdated

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .trending: return "Trending"
        case .latestAdded: return "New"
        case .latestUpdated: return "Updated"
        }
    }

    var list: NexusList {
        switch self {
        case .trending: return .trending
        case .latestAdded: return .latestAdded
        case .latestUpdated: return .latestUpdated
        }
    }
}

@MainActor
struct BrowseView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem
    @State private var tab: BrowseTab = .trending
    @State private var search = ""
    @State private var mods: [NexusModSummary] = []
    @State private var searchResults: [NexusModSummary]?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var detail: NexusModSummary?

    private var shown: [NexusModSummary] {
        if let searchResults { return searchResults }
        guard !search.isEmpty else { return mods }
        return mods.filter { ($0.name ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HDPage {
            HDPageTitle(title: "Browse", subtitle: "Helldivers 2 mods from Nexus Mods. Install with one click.")
            StatusBanner()
            if model.nexusAPIKey.isEmpty {
                HDBanner(
                    icon: "key.fill",
                    color: .hdYellow,
                    title: Text("Connect Nexus Mods"),
                    message: Text("Add your free Nexus Mods API key in Settings to browse and install mods here.")
                ) {
                    Button("Open Settings") { selection = .settings }
                        .buttonStyle(HDPrimaryButtonStyle())
                }
            } else {
                controls
                if model.nexusUser != nil && model.nexusUser?.is_premium != true {
                    Text("Free Nexus account: Install opens the mod page. Click “Mod Manager Download” there and Liberty Loader takes over.")
                        .font(.caption)
                        .foregroundStyle(Color.hdMuted)
                }
                content
            }
        }
        .navigationTitle("Browse")
        .task(id: tab) { await load() }
        .task { await model.refreshNexusUser() }
        .sheet(item: $detail) { mod in
            ModDetailSheet(mod: mod)
                .environment(model)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ForEach(BrowseTab.allCases) { item in
                HDChip(title: item.title, isSelected: tab == item && searchResults == nil) {
                    searchResults = nil
                    search = ""
                    tab = item
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.hdMuted)
                TextField("Search Nexus Mods", text: $search)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await runSearch() } }
                if !search.isEmpty {
                    Button {
                        search = ""
                        searchResults = nil
                    } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.hdMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 280)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            Button {
                Task { await load() }
            } label: { Image(systemName: "arrow.clockwise") }
            .buttonStyle(HDSecondaryButtonStyle())
            .help("Reload")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && shown.isEmpty {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        } else if let loadError {
            HDBanner(icon: "wifi.exclamationmark", color: .hdDanger, title: Text("Couldn't load mods"), message: Text(verbatim: loadError)) {
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(HDSecondaryButtonStyle())
            }
        } else if shown.isEmpty {
            Text("No mods found.").foregroundStyle(Color.hdMuted)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                ForEach(shown) { mod in
                    BrowseCard(mod: mod) { detail = mod }
                }
            }
        }
    }

    private func load() async {
        guard !model.nexusAPIKey.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            mods = try await NexusClient(apiKey: model.nexusAPIKey).list(tab.list)
            loadError = nil
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func runSearch() async {
        let term = search.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { searchResults = nil; return }
        isLoading = true
        defer { isLoading = false }
        // Falls back to filtering the current list when the search API isn't available.
        searchResults = await NexusClient(apiKey: model.nexusAPIKey).search(term)
    }
}

@MainActor
struct BrowseCard: View {
    @Environment(AppModel.self) private var model
    let mod: NexusModSummary
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                RemoteImage(url: mod.pictureURL)
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        if let installed = model.installedMod(for: mod.id) {
                            Group {
                                if installed.hasUpdate {
                                    HDTag(text: "Update", color: .hdInfo)
                                } else {
                                    HDTag(text: "Installed", color: .hdSuccess)
                                }
                            }
                            .background(Color.black.opacity(0.7))
                            .padding(8)
                        }
                    }
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: mod.name ?? "")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.hdText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(verbatim: mod.summary ?? "")
                        .font(.caption)
                        .foregroundStyle(Color.hdMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 10) {
                        if let author = mod.author {
                            Label { Text(verbatim: author) } icon: { Image(systemName: "person.fill") }
                        }
                        if let endorsements = mod.endorsement_count {
                            Label { Text(verbatim: "\(endorsements)") } icon: { Image(systemName: "hand.thumbsup.fill") }
                        }
                    }
                    .font(.hdLabel(10))
                    .foregroundStyle(Color.hdMuted)
                    .lineLimit(1)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.hdPanel)
            .clipShape(CutCornerShape())
            .overlay(CutCornerShape().stroke(isHovered ? Color.hdYellow.opacity(0.6) : Color.hdBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

@MainActor
struct ModDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mod: NexusModSummary
    @State private var isInstalling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: mod.pictureURL)
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: mod.name ?? "")
                    .font(.hdDisplay(30))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hdText)
                HStack(spacing: 14) {
                    if let author = mod.author {
                        Label { Text(verbatim: author) } icon: { Image(systemName: "person.fill") }
                    }
                    if let version = mod.version {
                        Label { Text(verbatim: "v\(version)") } icon: { Image(systemName: "tag.fill") }
                    }
                    if let endorsements = mod.endorsement_count {
                        Label { Text(verbatim: "\(endorsements)") } icon: { Image(systemName: "hand.thumbsup.fill") }
                    }
                }
                .font(.hdLabel(11))
                .foregroundStyle(Color.hdMuted)
                ScrollView {
                    Text(verbatim: mod.summary ?? "")
                        .foregroundStyle(Color.hdText.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                HStack(spacing: 10) {
                    Button {
                        isInstalling = true
                        Task {
                            await model.installFromBrowser(mod)
                            isInstalling = false
                            dismiss()
                        }
                    } label: {
                        Label {
                            if isInstalling {
                                Text("Installing…")
                            } else if model.installedMod(for: mod.id) != nil {
                                Text("Reinstall")
                            } else {
                                Text("Install")
                            }
                        } icon: { Image(systemName: "arrow.down.circle.fill") }
                    }
                    .buttonStyle(HDPrimaryButtonStyle())
                    .disabled(isInstalling)
                    Button("Open on Nexus Mods") { NSWorkspace.shared.open(mod.pageURL) }
                        .buttonStyle(HDSecondaryButtonStyle())
                    Spacer()
                    Button("Close") { dismiss() }
                        .buttonStyle(HDSecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(22)
        }
        .frame(width: 560)
        .background(Color.hdBackground)
        .preferredColorScheme(.dark)
    }
}

/// Loads a remote picture with a dark placeholder.
@MainActor
struct RemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.hdPanelRaised
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.hdYellow.opacity(0.35))
                }
            }
        }
    }
}
