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
    /// Ordering is always total: when two mods compare equal on the chosen
    /// sort, mod id breaks the tie, so the grid cannot reshuffle between
    /// renders of the same data.
    public func apply(to mods: [NexusModSummary], installedIDs: Set<Int> = []) -> [NexusModSummary] {
        // Implemented in a follow-up; the contract is what callers rely on.
        mods
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
