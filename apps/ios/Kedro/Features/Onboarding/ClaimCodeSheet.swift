import SwiftUI

/// Claim codes typed or pasted on this phone ("Got a claim code?", design §5.1, PRD §3.2), kept
/// until an account can claim them with `POST /v1/claims`.
nonisolated enum PendingClaims {
    static let defaultsKey = "kedro.pendingClaimCodes"

    /// Pulls the code out of what was typed: a bare code, or a claim link
    /// (`https://kedro.app/claim/<code>` or `…?code=<code>`). Codes are 6–64 letters, digits or dashes.
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
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard (6...64).contains(candidate.count),
              candidate.unicodeScalars.allSatisfy(allowed.contains)
        else { return nil }
        return candidate
    }

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

/// "Got a claim code?": paste the code (or link) someone sent you after a game you played as a
/// guest. Saved on the phone and claimed when you sign in.
struct ClaimCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var saved = false

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
                        // TODO(networking): POST /v1/claims {claimToken} once signed in; remove on success.
                        PendingClaims.add(code)
                        saved = true
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
