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
    @State private var isLoadingMore = false
    @State private var loadError: String?
    @State private var detail: NexusModSummary?
    @State private var sort: BrowseQuery.Sort = .nexus
    @State private var hideInstalled = false
    @State private var allowAdult = false
    @State private var page = 0
    @State private var hasMore = false

    private static let pageSize = 40

    private var query: BrowseQuery {
        // Server-side search already matched the term, so re-applying it here
        // would only narrow results the API deliberately returned.
        BrowseQuery(text: searchResults == nil ? search : "",
                    sort: sort, hideInstalled: hideInstalled, allowAdult: allowAdult)
    }

    private var shown: [NexusModSummary] {
        query.apply(to: searchResults ?? mods, installedIDs: model.installedNexusIDs)
    }

    /// Paging only makes sense on a browse list, not on a search result set.
    private var canLoadMore: Bool { searchResults == nil && hasMore && !isLoading }

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
                filters
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
                    .help("Filters as you type; press Return to search all of Nexus Mods.")
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

    private var filters: some View {
        HStack(spacing: 14) {
            Picker("Sort", selection: $sort) {
                Text("Nexus order").tag(BrowseQuery.Sort.nexus)
                Text("Most endorsed").tag(BrowseQuery.Sort.endorsements)
                Text("Name").tag(BrowseQuery.Sort.name)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
            .help("“Nexus order” keeps the ranking Nexus returned for this tab.")

            Toggle("Hide installed", isOn: $hideInstalled)
                .toggleStyle(.checkbox)
            Toggle("Show adult", isOn: $allowAdult)
                .toggleStyle(.checkbox)
                .help("Adult mods are hidden unless you ask for them.")

            Spacer()

            if !shown.isEmpty {
                Text(resultCount)
                    .font(.hdLabel(10))
                    .foregroundStyle(Color.hdMuted)
            }
        }
        .font(.caption)
        .foregroundStyle(Color.hdMuted)
    }

    private var resultCount: String {
        let total = (searchResults ?? mods).count
        let visible = shown.count
        return visible == total
            ? String(localized: "\(visible) mods")
            : String(localized: "\(visible) of \(total) mods")
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
            // Distinguish "Nexus returned nothing" from "your filters hid it all",
            // because the fix is different.
            VStack(spacing: 10) {
                Text(filtersHidEverything ? "Every mod here is filtered out." : "No mods found.")
                    .foregroundStyle(Color.hdMuted)
                if filtersHidEverything {
                    Button("Clear filters") {
                        sort = .nexus
                        hideInstalled = false
                        allowAdult = false
                        search = ""
                        searchResults = nil
                    }
                    .buttonStyle(HDSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                ForEach(shown) { mod in
                    BrowseCard(mod: mod) { detail = mod }
                }
            }
            if canLoadMore {
                Button {
                    Task { await loadMore() }
                } label: {
                    if isLoadingMore { Text("Loading…") } else { Text("Load more") }
                }
                .buttonStyle(HDSecondaryButtonStyle())
                .disabled(isLoadingMore)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
        }
    }

    /// True when Nexus returned mods but the current filters hide all of them.
    private var filtersHidEverything: Bool {
        !(searchResults ?? mods).isEmpty
    }

    private func load() async {
        guard !model.nexusAPIKey.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            page = 0
            let first = try await NexusClient(apiKey: model.nexusAPIKey)
                .list(tab.list, page: 0, pageSize: Self.pageSize)
            mods = first.mods
            hasMore = first.hasMore
            loadError = nil
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadMore() async {
        guard canLoadMore, !model.nexusAPIKey.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = page + 1
        guard let more = try? await NexusClient(apiKey: model.nexusAPIKey)
            .list(tab.list, page: next, pageSize: Self.pageSize) else { return }
        // Nexus can repeat a mod across pages; appending blindly would give
        // SwiftUI duplicate ids and a broken grid.
        let known = Set(mods.map(\.mod_id))
        mods += more.mods.filter { !known.contains($0.mod_id) }
        hasMore = more.hasMore
        page = next
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
    @State private var requirements: [NexusRequirement]?

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
                requirementsSection
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
        .task {
            // Requirements are not in the list payload, so this is the first
            // chance to say what a mod needs — before it is downloaded.
            requirements = await NexusClient(apiKey: model.nexusAPIKey)
                .requirements(modID: mod.id) ?? []
        }
    }

    /// What this mod needs, shown before installing rather than after.
    ///
    /// A mod needing Bingus or HD2Runtime runs code in the game, which is the
    /// browse-time counterpart of CosmeticCheck's runtimeDependency signal.
    @ViewBuilder
    private var requirementsSection: some View {
        if let requirements {
            let needed = requirements.filter { !$0.isModManager }
            if needed.isEmpty {
                Text("No required mods listed.")
                    .font(.caption)
                    .foregroundStyle(Color.hdMuted)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if needed.needsModRuntime {
                        HStack(spacing: 6) {
                            HDTag(text: "Runs code", color: .hdYellow)
                            Text("Needs a mod runtime that patches the game while it runs.")
                                .font(.caption)
                                .foregroundStyle(Color.hdMuted)
                        }
                    }
                    Text("Requires: \(needed.map(\.name).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Color.hdMuted)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Loads a remote picture with a dark placeholder.
@MainActor
struct RemoteImage: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image ?? url.flatMap({ ImageCache.shared.cached($0) }) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.hdPanelRaised
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.hdYellow.opacity(0.35))
                }
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await ImageCache.shared.load(url)
        }
    }
}
