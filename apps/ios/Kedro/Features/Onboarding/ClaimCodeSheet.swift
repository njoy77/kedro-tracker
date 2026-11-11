import SwiftUI

/// Claim codes typed or pasted on this phone ("Got a claim code?", design §5.1, PRD §3.2), kept
/// until an account can claim them with `POST /v1/claims`.
nonisolated enum PendingClaims {
    static let defaultsKey = "kedro.pendingClaimCodes"

    /// Pulls the code out of what was typed: a bare code, or a claim link
    /// (`https://playkedro.com/claim/<code>` or `…?code=<code>`).
    static func code(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = trimmed
        if let url = URL(string: trimmed), url.scheme != nil {
            if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value {
                candidate = query
            } else {
                candidate = url.lastPathComponent
            }
        }
        return isValid(candidate) ? candidate : nil
    }

    /// Codes are 6–64 URL-safe characters: ASCII letters, digits, `-` and `_`. That covers the
    /// base64url codes hosts make (`GuestClaimCodes.newCode()`) and imported `kedro-legacy-<hex>`
    /// codes; the server takes 16–256.
    static func isValid(_ code: String) -> Bool {
        (6...64).contains(code.count) && code.unicodeScalars.allSatisfy(allowedScalars.contains)
    }

    private static let allowedScalars = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".unicodeScalars)

    static func all(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: defaultsKey) ?? []
    }

    static func add(_ code: String, defaults: UserDefaults = .standard) {
        var codes = all(defaults: defaults)
        guard !codes.contains(code) else { return }
        codes.append(code)
        defaults.set(codes, forKey: defaultsKey)
    }

    static func remove(_ code: String, defaults: UserDefaults = .standard) {
        defaults.set(all(defaults: defaults).filter { $0 != code }, forKey: defaultsKey)
    }
}

/// A claim link the app was opened with (a universal link from the claim message, or Kedro's
/// own scheme):
/// - `https://playkedro.com/claim/<code>`
/// - `https://playkedro.com/claim?code=<code>`
/// - `kedro://claim/<code>`
///
/// Opening one shows "Claim Your Games" with the code filled in. Other links aren't claim links.
nonisolated struct ClaimLink: Hashable, Sendable, Identifiable {
    /// nil when the link's code isn't a valid one (the sheet then opens empty).
    var code: String?

    var id: String { code ?? "" }

    init(code: String?) {
        self.code = code
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var parts = components.path.split(separator: "/").map(String.init)
        switch components.scheme?.lowercased() {
        case "https", "http":
            guard let host = components.host?.lowercased(), host == KedroLink.webHost || host == "www.\(KedroLink.webHost)" else { return nil }
        case KedroLink.scheme:
            // kedro://claim/<code>: the first segment arrives as the host.
            if let host = components.host { parts.insert(host, at: 0) }
        default:
            return nil
        }
        guard parts.first?.lowercased() == "claim", parts.count <= 2 else { return nil }
        let candidate = parts.count == 2 ? parts[1] : components.queryItems?.first { $0.name == "code" }?.value
        code = candidate.flatMap { PendingClaims.isValid($0) ? $0 : nil }
    }
}

/// "Got a claim code?": paste the code (or link) someone sent you after a game you played as a
/// guest. Saved on the phone and claimed when you sign in.
struct ClaimCodeSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    @State private var saved = false

    /// - Parameter code: a code to fill in (an opened claim link).
    init(code: String? = nil) {
        _input = State(initialValue: code ?? "")
    }

    private var code: String? { PendingClaims.code(from: input) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Code or link", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Claim code or link")
                } footer: {
                    if saved {
                        Text("Saved. Sign in and those games become yours.")
                    } else if !input.isEmpty && code == nil {
                        Text("That doesn't look like a claim code. Paste the whole link if you have one.")
                    } else {
                        Text("Played as a guest? Whoever hosted can send you a code from the game's end screen.")
                    }
                }
            }
            .navigationTitle("Claim Your Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saved ? Literal.text("button.done") : "Save") {
                        if saved { return dismiss() }
                        guard let code else { return }
                        // Kept on the phone; POST /v1/claims now if signed in, else at sign-in
                        // (AccountSync removes it once the server accepts it).
                        PendingClaims.add(code)
                        saved = true
                        if let account = app.account, app.profile?.isGuest == false {
                            Task { _ = await account.claimGuestHistory(guestToken: nil) }
                        }
                    }
                    .disabled(!saved && code == nil)
                }
            }
        }
    }
}

#Preview {
    ClaimCodeSheet()
        .previewEnvironment()
}

#Preview("From a link") {
    ClaimCodeSheet(code: "kedro-legacy-4f6c2a")
        .previewEnvironment()
}
