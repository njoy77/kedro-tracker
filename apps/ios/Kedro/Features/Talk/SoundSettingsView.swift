import SwiftUI

/// Settings → Sounds (design §3.8): the master switch (off by default), a toggle and a preview
/// button per moment, and the Table speaker setting. Push it from Settings:
///
/// ```swift
/// NavigationLink("Sounds") { SoundSettingsView() }
/// ```
///
/// or embed `SoundSettingsSections()` in an existing `Form`.
struct SoundSettingsView: View {
    var body: some View {
        Form {
            SoundSettingsSections()
        }
        .scrollContentBackground(.hidden)
        .background(.surface)
        .navigationTitle("Sounds")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The Sounds sections, for embedding in a `Form`.
struct SoundSettingsSections: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(ToastCenter.self) private var toasts
    @State private var services = TalkServices.shared

    private var voice: Voice { Voice(level: prefs.effectiveLanguageLevel) }

    var body: some View {
        @Bindable var sounds = prefs.sounds
        Section {
            Toggle("Sounds", isOn: Binding {
                sounds.isEnabled
            } set: { isOn in
                sounds.isEnabled = isOn
                if isOn { toasts.show(voice.line("SN-03")) }
            })
            .tint(.kedroRed)
        } footer: {
            Text(voice.line("SN-01"))
        }

        Section("Moments") {
            ForEach(SoundMoment.allCases) { moment in
                momentRow(moment)
            }
        }
        .disabled(!sounds.isEnabled)

        Section {
            Picker("Table speaker", selection: $sounds.tableSpeaker) {
                ForEach(TableSpeakerPreference.allCases, id: \.self) { preference in
                    Text(preference.title).tag(preference)
                }
            }
        } footer: {
            Text(voice.line("SN-02"))
        }
        .disabled(!sounds.isEnabled)
    }

    private func momentRow(_ moment: SoundMoment) -> some View {
        HStack(spacing: 12) {
            Button {
                services.sound.preview(moment)
            } label: {
                Image(systemName: "play.circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .tint(.kedroRed)
            .accessibilityLabel("Play \(moment.title)")
            Toggle(isOn: Binding {
                prefs.sounds.isOn(moment)
            } set: {
                prefs.sounds.set(moment, on: $0)
            }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(moment.title)
                    Text(moment.detail)
                        .font(.caption)
                        .foregroundStyle(.silver)
                }
            }
            .tint(.kedroRed)
        }
    }
}

/// "Be the table speaker" for the Table's ⋯ menu (design §3.8). Shows a check when this phone
/// already plays the shared sounds.
struct TableSpeakerButton: View {
    let session: GameSession

    @Environment(AppPreferences.self) private var prefs

    private var isThisPhone: Bool {
        TableSpeaker.device(for: session.state) == session.identity.deviceID
    }

    var body: some View {
        Button {
            Task { try? await session.claimTableSpeaker() }
        } label: {
            if isThisPhone {
                Label("You're the table speaker", systemImage: "checkmark")
            } else {
                Label("Be the table speaker", systemImage: "hifispeaker")
            }
        }
        .disabled(isThisPhone || !session.state.status.isLive)
    }
}

#Preview("Settings") {
    NavigationStack {
        SoundSettingsView()
    }
    .previewEnvironment()
}

#Preview("Table menu") {
    Menu("More", systemImage: "ellipsis") {
        TableSpeakerButton(session: PreviewData.sampleSession())
    }
    .padding()
    .previewEnvironment()
}
