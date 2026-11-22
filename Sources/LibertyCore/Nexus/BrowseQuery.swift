import Foundation

/// How the Browse tab narrows and orders what Nexus Mods returned.
///
/// Kept out of the view so it can be tested: the filtering rules are the part
/// most likely to be wrong, and the view layer cannot be compiled on a machine
/// without Xcode.
public struct BrowseQuery: Equatable, Sendable {

    public enum Sort: String, CaseIterable, Equatable, Sendable, Codable {
        /// Whatever order Nexus returned — trending, newest, recently updated.
        case nexus
        case endorsements
        case name

        public var isDefault: Bool { self == .nexus }
    }

    /// Free text typed by the user. Matched against name, summary and author.
    public var text: String
    public var sort: Sort
    /// Hide mods already installed, for finding something new.
    public var hideInstalled: Bool
    /// Adult mods are hidden unless the user asks for them. `NexusModSummary`
    /// already carries the flag; this is the only place it becomes a choice.
    public var allowAdult: Bool

    public init(text: String = "", sort: Sort = .nexus,
                hideInstalled: Bool = false, allowAdult: Bool = false) {
        self.text = text
        self.sort = sort
        self.hideInstalled = hideInstalled
        self.allowAdult = allowAdult
    }

    public var isDefault: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
            && sort.isDefault && !hideInstalled && !allowAdult
    }

    /// Narrows and orders `mods`.
    ///
    /// `installedIDs` are the Nexus mod ids already installed. Pass an empty
    /// set when that is unknown; the result is then simply unfiltered by it.
    ///
    /// Ordering is always deterministic, so the grid cannot reshuffle between
    /// renders of the same data. `.nexus` keeps the incoming order exactly —
    /// that order *is* the ranking Nexus returned, so breaking its "ties" by
    /// mod id would throw the ranking away. The other sorts break ties by mod
    /// id, then by incoming index so duplicate ids stay stable.
    public func apply(to mods: [NexusModSummary], installedIDs: Set<Int> = []) -> [NexusModSummary] {
        var result = mods.filter { $0.passesVisibility(allowAdult: allowAdult) }
        if hideInstalled {
            result = result.filter { !installedIDs.contains($0.mod_id) }
        }
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if !words.isEmpty {
            result = result.filter { mod in
                let fields = [mod.name, mod.summary, mod.author].compactMap { $0 }
                return words.allSatisfy { word in
                    fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                }
            }
        }

        // Swift's sort is not stable, so the comparator is made total: the
        // incoming index is the final tiebreak (it only matters for duplicate ids).
        let indexed = Array(result.enumerated())
        let ordered: [(offset: Int, element: NexusModSummary)]
        switch sort {
        case .nexus:
            ordered = indexed
        case .endorsements:
            ordered = indexed.sorted { a, b in
                let x = a.element.endorsement_count ?? 0, y = b.element.endorsement_count ?? 0
                if x != y { return x > y }
                return Self.idThenIndex(a, b)
            }
        case .name:
            ordered = indexed.sorted { a, b in
                switch (a.element.name, b.element.name) {
                case let (x?, y?):
                    let c = x.localizedStandardCompare(y)
                    if c != .orderedSame { return c == .orderedAscending }
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): break
                }
                return Self.idThenIndex(a, b)
            }
        }
        return ordered.map(\.element)
    }

    private static func idThenIndex(_ a: (offset: Int, element: NexusModSummary),
                                    _ b: (offset: Int, element: NexusModSummary)) -> Bool {
        if a.element.mod_id != b.element.mod_id { return a.element.mod_id < b.element.mod_id }
        return a.offset < b.offset
    }
}

extension NexusModSummary {
    /// Whether this mod should be shown when adult content is `allowed`.
    ///
    /// `isListable` is the hard rule and always applies — a mod that is
    /// unavailable cannot be installed, so showing it is a dead end. Adult
    /// content is the soft one the user can opt into.
    public func passesVisibility(allowAdult: Bool) -> Bool {
        guard name != nil, available != false else { return false }
        return allowAdult || contains_adult_content != true
    }
}
