import SwiftUI

/// Types and checks an @handle as you go: format first, then availability (debounced), with
/// suggestions from the first name (design §5.1). Used by onboarding and Settings → Profile.
struct HandleField: View {
    @Binding var text: String
    /// The result the parent acts on: a free, valid handle, or nil.
    @Binding var accepted: Handle?
    var firstName: String
    /// The handle this player already has (always counts as available).
    var current: Handle?

    @Environment(AppModel.self) private var app
    @State private var problem: HandleProblem?
    @State private var isChecking = false
    @State private var suggestions: [Handle] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 2) {
                Text("@").foregroundStyle(.silver)
                TextField("handle", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .submitLabel(.done)
                    .accessibilityLabel("Handle")
                if isChecking {
                    ProgressView().controlSize(.small)
                } else if accepted != nil {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.cream)
                        .accessibilityLabel("Available")
                }
            }
            .font(.title3)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(.surface, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(problem == nil ? Color.rule : .kedroRed)
            }

            Group {
                if let problem {
                    Text(problem.message).foregroundStyle(.kedroRed)
                } else {
                    Text("Lowercase letters, numbers, dots and underscores. Change it later in Settings.")
                        .foregroundStyle(.silverDim)
                }
            }
            .font(.footnote)

            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { handle in
                            Button(handle.description) { text = handle.rawValue }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(.surfaceRaised, in: .capsule)
                                .foregroundStyle(.cream)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .task(id: text) { await check(text) }
        .task(id: firstName) { await loadSuggestions() }
    }

    private var checker: any HandleAvailabilityChecking {
        (app.directory as? any HandleAvailabilityChecking) ?? DirectoryHandleAvailability(directory: app.directory)
    }

    private func check(_ input: String) async {
        accepted = nil
        switch HandleValidation.validate(input) {
        case .failure(let failure):
            problem = input.isEmpty ? nil : failure
            return
        case .success(let handle):
            problem = nil
            if handle == current {
                accepted = handle
                return
            }
            isChecking = true
            defer { isChecking = false }
            do {
                try await Task.sleep(for: .milliseconds(350))
                let free = try await checker.isAvailable(handle, for: app.profile?.identity)
                problem = free ? nil : .taken
                accepted = free ? handle : nil
            } catch is CancellationError {
                return
            } catch {
                // Offline: accept the format; the API has the final word when the profile syncs.
                accepted = handle
            }
        }
    }

    private func loadSuggestions() async {
        var taken = Set<String>()
        for candidate in Handle.suggestions(firstName: firstName, count: 8) where candidate != current {
            if (try? await checker.isAvailable(candidate, for: app.profile?.identity)) == false {
                taken.insert(candidate.rawValue)
            }
        }
        suggestions = HandleValidation.uniqueSuggestions(firstName: firstName, taken: taken)
        if text.isEmpty, let first = current ?? suggestions.first {
            text = first.rawValue
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @State var accepted: Handle?
    HandleField(text: $text, accepted: $accepted, firstName: "Noah")
        .padding()
        .background(.night)
        .previewEnvironment()
        .preferredColorScheme(.dark)
}
