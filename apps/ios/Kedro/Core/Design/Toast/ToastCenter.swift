import Foundation
import Observation

/// A non-modal message that slides in from the top (design §3.7, §6.5, §8.1).
struct Toast: Identifiable {
    enum Kind: Equatable {
        /// "Round 6 saved · Undo", "Ana sat down · Remove".
        case info
        /// "Ana → Noah: Knocking on that? Brave." (tap opens the feed)
        case taunt
        /// "LIVE KNOCK · Sam knocked. Last turns. Pray." (red edge)
        case liveKnock
    }

    struct Action {
        var title: String
        var perform: @MainActor () -> Void
    }

    let id = UUID()
    var kind: Kind = .info
    /// The face on the left (taunt sender, knocker, the person who sat down).
    var avatar: Avatar?
    var avatarName: String?
    var avatarIsGuest = false
    /// Small line above the message: "LIVE KNOCK", "Ana → Noah", "Ana → the table · custom".
    var eyebrow: String?
    var message: String
    /// A trailing button ("Undo", "Remove").
    var action: Action?
    /// What tapping the toast does (open the feed).
    var onTap: (@MainActor () -> Void)?
    /// How long it stays. Taunts 4 s, live knocks and undo toasts 5 s.
    var duration: Duration = .seconds(4)
    /// The VoiceOver announcement ("Ana to Noah: …"). Defaults to the eyebrow and message.
    var announcement: String?

    var spokenText: String {
        announcement ?? [eyebrow, message].compactMap(\.self).joined(separator: ": ")
    }
}

/// The app's toast queue. One instance in `AppModel`, rendered by `.toastHost()`.
///
/// Rules (design §6.5): at most 3 on screen; while a Round sheet is open (`isDeferring`) toasts
/// queue and appear after it closes, with older ones collapsing into "+2 more in the feed".
/// Nothing ever covers the Record Round button or the Round sheet.
@Observable
final class ToastCenter {
    static let maxVisible = 3

    /// On screen now, oldest first.
    private(set) var visible: [Toast] = []
    /// Waiting for the Round sheet to close.
    private(set) var deferred: [Toast] = []
    /// Toasts that collapsed into "+n more in the feed".
    private(set) var overflowCount = 0

    /// Set while a Round sheet (or anything that must not be covered) is open.
    var isDeferring = false {
        didSet {
            if oldValue && !isDeferring { flushDeferred() }
        }
    }

    @ObservationIgnored private var timers: [UUID: Task<Void, Never>] = [:]

    func show(_ toast: Toast) {
        if isDeferring {
            deferred.append(toast)
        } else {
            present([toast])
        }
    }

    /// Convenience for a plain info toast.
    func show(_ message: String, action: Toast.Action? = nil, duration: Duration = .seconds(4)) {
        show(Toast(message: message, action: action, duration: duration))
    }

    func dismiss(_ id: Toast.ID) {
        timers[id]?.cancel()
        timers[id] = nil
        visible.removeAll { $0.id == id }
        if visible.isEmpty { overflowCount = 0 }
    }

    func dismissAll() {
        for id in visible.map(\.id) { dismiss(id) }
        deferred.removeAll()
        overflowCount = 0
    }

    /// Runs a toast's action, then dismisses it.
    func performAction(of id: Toast.ID) {
        guard let toast = visible.first(where: { $0.id == id }) else { return }
        dismiss(id)
        toast.action?.perform()
    }

    /// Runs a toast's tap handler, then dismisses it.
    func tap(_ id: Toast.ID) {
        guard let toast = visible.first(where: { $0.id == id }) else { return }
        dismiss(id)
        toast.onTap?()
    }

    // MARK: Private

    private func flushDeferred() {
        let queued = deferred
        deferred.removeAll()
        present(queued)
    }

    private func present(_ toasts: [Toast]) {
        guard !toasts.isEmpty else { return }
        visible.append(contentsOf: toasts)
        while visible.count > Self.maxVisible {
            let oldest = visible.removeFirst()
            timers[oldest.id]?.cancel()
            timers[oldest.id] = nil
            overflowCount += 1
        }
        for toast in toasts where visible.contains(where: { $0.id == toast.id }) {
            scheduleDismissal(of: toast)
        }
    }

    private func scheduleDismissal(of toast: Toast) {
        let id = toast.id
        timers[id] = Task { [weak self] in
            try? await Task.sleep(for: toast.duration)
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }
}
