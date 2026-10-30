import AVFoundation
import OSLog

/// Something that can play the sound pack (the real player, or a recorder in tests).
protocol SoundPlaying: AnyObject {
    /// Plays a moment now, if the settings allow it on this phone.
    func play(_ moment: SoundMoment, settings: SoundSettings)
    /// Settings → Sounds preview button: plays regardless of the switches.
    func preview(_ moment: SoundMoment)
}

extension SoundPlaying {
    /// Plays cues in order, each after its delay. Returns when the last one has started.
    func play(_ cues: [SoundCue], settings: SoundSettings) async {
        let clock = ContinuousClock()
        let start = clock.now
        for cue in cues.sorted(by: { $0.delay < $1.delay }) {
            try? await clock.sleep(until: start + cue.delay)
            guard !Task.isCancelled else { return }
            play(cue.moment, settings: settings)
        }
    }
}

/// Plays the sound pack with `AVAudioPlayer` on the `.ambient` audio session (design §3.8): it
/// respects the Silent switch, mixes with whatever music is playing and never ducks it.
final class SoundPlayer: SoundPlaying {
    let pack: SoundPack

    private var players: [SoundMoment: AVAudioPlayer] = [:]
    private var isSessionConfigured = false
    private let bundle: Bundle
    private let log = Logger(subsystem: "com.njoy77.kedro", category: "Sound")

    init(pack: SoundPack = .classic, bundle: Bundle = .main) {
        self.pack = pack
        self.bundle = bundle
    }

    func play(_ moment: SoundMoment, settings: SoundSettings) {
        guard settings.plays(moment) else { return }
        start(moment)
    }

    func preview(_ moment: SoundMoment) {
        start(moment)
    }

    /// Loads every sound so the first knock doesn't lag. Optional; `play` loads on demand.
    func preload() {
        for moment in SoundMoment.allCases { _ = player(for: moment) }
    }

    /// The bundled file for a moment (nil if it's missing from the build).
    func url(for moment: SoundMoment) -> URL? {
        let name = pack.resourceName(for: moment)
        return bundle.url(forResource: name, withExtension: SoundPack.fileExtension)
            ?? bundle.url(forResource: name, withExtension: SoundPack.fileExtension, subdirectory: "Sounds")
    }

    // MARK: Private

    private func start(_ moment: SoundMoment) {
        configureSessionIfNeeded()
        guard let player = player(for: moment) else { return }
        player.currentTime = 0
        player.play()
    }

    private func player(for moment: SoundMoment) -> AVAudioPlayer? {
        if let cached = players[moment] { return cached }
        guard let url = url(for: moment) else {
            log.error("Missing sound \(self.pack.resourceName(for: moment), privacy: .public)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = SoundPack.volume
            player.prepareToPlay()
            players[moment] = player
            return player
        } catch {
            log.error("Couldn't load \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func configureSessionIfNeeded() {
        guard !isSessionConfigured else { return }
        isSessionConfigured = true
        do {
            // .ambient: silenced by the Silent switch and mixed with other audio, never ducking it.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log.error("Audio session: \(error.localizedDescription, privacy: .public)")
        }
    }
}
