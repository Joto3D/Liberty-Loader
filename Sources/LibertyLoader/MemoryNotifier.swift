import AppKit
import LibertyCore
import UserNotifications

/// Warns with a macOS notification when Helldivers 2 is about to run out of memory.
@MainActor
enum MemoryNotifier {
    static func notify(_ level: MemoryLevel, footprint: UInt64) {
        let amount = GameMemory.format(footprint)
        let title: String
        let body: String
        switch level {
        case .critical:
            title = String(localized: "Memory critical")
            body = String(localized: "Helldivers 2 is using \(amount). The game may crash soon: finish the mission and restart the game.")
        case .high:
            title = String(localized: "Memory is getting high")
            body = String(localized: "Helldivers 2 is using \(amount). Restart the game after this mission.")
        case .normal:
            return
        }
        NSSound.beep()
        // UNUserNotificationCenter traps outside a bundled app (e.g. `swift run`).
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: "memory-\(level.rawValue)", content: content, trigger: nil))
        }
    }
}
