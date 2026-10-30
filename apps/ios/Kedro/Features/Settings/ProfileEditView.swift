import SwiftUI

/// Settings → your name, face and @handle (design §5.1: "changeable later"). Guests change their
/// name only: unclaimed guests don't pick a face or handle (§3.5).
struct ProfileEditView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar: Avatar?
    @State private var handleText = ""
    @State private var handle: Handle?
    @State private var loaded = false

    private var profile: LocalProfile? { app.profile }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        guard let profile, !trimmedName.isEmpty else { return false }
        return profile.isGuest || handle != nil
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("First name", text: $name)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
            }
            if profile?.isGuest == false {
                Section("Handle") {
                    HandleField(text: $handleText, accepted: $handle, firstName: trimmedName, current: profile?.handle)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                Section("Face") {
                    AvatarPicker(
                        avatar: $avatar,
                        name: trimmedName.isEmpty ? "You" : trimmedName,
                        unlocked: profile.map { StatsModel.shared(for: app.store).snapshot.unlockedSecretAvatars(for: $0.identity) } ?? []
                    )
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            } else {
                Section {
                    Text("Sign in to pick a face and a handle. Everything you played as a guest comes with you.")
                        .font(.footnote)
                        .foregroundStyle(.silver)
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(!canSave)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded, let profile else { return }
        loaded = true
        name = profile.displayName
        avatar = profile.avatar
        handleText = profile.handle?.rawValue ?? ""
        handle = profile.handle
    }

    private func save() {
        guard var updated = profile, canSave else { return }
        updated.displayName = trimmedName
        if !updated.isGuest {
            updated.avatar = avatar ?? updated.avatar
            updated.handle = handle ?? updated.handle
        }
        app.profiles.save(updated)
        // PUT /v1/players/me (a local photo stays on the phone until photo upload exists). A 409
        // means the handle was taken meanwhile: keep the sheet open so another can be picked.
        Task {
            if await app.syncProfile() == .handleTaken {
                handle = nil
                app.toasts.show(HandleProblem.taken.message)
                return
            }
            dismiss()
        }
    }
}

#Preview {
    NavigationStack { ProfileEditView() }
        .previewEnvironment()
}
