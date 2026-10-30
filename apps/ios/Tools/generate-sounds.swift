#!/usr/bin/env swift
// Generates the Classic sound pack in apps/ios/Kedro/Resources/Sounds (design §3.8).
//
//   swift apps/ios/Tools/generate-sounds.swift            (from the repo root)
//
// - classic-winner.caf: the Kedro neigh, converted from apps/web/public/neigh.mp4 with afconvert,
//   trimmed to the 3 s budget (leading silence removed, short fade out) and brought down from the
//   source's clipped level.
// - Every other file is a PLACEHOLDER synthesized here (noise bursts, sines and simple envelopes)
//   so the sound pipeline can ship and be tested end to end. Replace them with professionally
//   produced sounds before launch; keep the file names, the 1.5 s limit and the -6 dBFS peak level.
//   `SoundPack.classic` in Core/Sound marks which moments are still placeholders.
//
// Output: mono AAC in a CAF container (small, plays with AVAudioPlayer). Requires macOS with
// afconvert (ships with macOS).

import AVFoundation
import Foundation

let sampleRate = 44_100.0
/// Every file peaks here: quiet by default, and the same level across the pack.
let peakLevel: Float = 0.5

let toolsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let iosURL = toolsURL.deletingLastPathComponent()
let repoURL = iosURL.deletingLastPathComponent().deletingLastPathComponent()
let outputURL = iosURL.appending(path: "Kedro/Resources/Sounds")
let neighSource = repoURL.appending(path: "apps/web/public/neigh.mp4")
let scratch = FileManager.default.temporaryDirectory.appending(path: "kedro-sounds-\(UUID().uuidString)")

// MARK: - Helpers

func run(_ tool: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "generate-sounds", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "\(tool) \(arguments.joined(separator: " ")) failed"])
    }
}

/// Deterministic noise so regenerating gives identical files.
struct Noise {
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    mutating func next() -> Float {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Float(Double(state % 2_000_001) / 1_000_000 - 1)
    }
}

func samples(seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * sampleRate)) }

func time(_ index: Int) -> Double { Double(index) / sampleRate }

/// One-pole low-pass, in place.
func lowPass(_ buffer: inout [Float], cutoff: Double) {
    let rc = 1 / (2 * Double.pi * cutoff)
    let alpha = Float((1 / sampleRate) / (rc + 1 / sampleRate))
    var previous: Float = 0
    for index in buffer.indices {
        previous += alpha * (buffer[index] - previous)
        buffer[index] = previous
    }
}

/// One-pole high-pass, in place.
func highPass(_ buffer: inout [Float], cutoff: Double) {
    let rc = 1 / (2 * Double.pi * cutoff)
    let alpha = Float(rc / (rc + 1 / sampleRate))
    var previousIn: Float = 0
    var previousOut: Float = 0
    for index in buffer.indices {
        let input = buffer[index]
        previousOut = alpha * (previousOut + input - previousIn)
        previousIn = input
        buffer[index] = previousOut
    }
}

func mix(_ source: [Float], into target: inout [Float], at seconds: Double, gain: Float = 1) {
    let offset = Int(seconds * sampleRate)
    for (index, value) in source.enumerated() where offset + index < target.count {
        target[offset + index] += value * gain
    }
}

/// Short fades at both ends so nothing clicks.
func fadeEdges(_ buffer: inout [Float], fadeIn: Double = 0.003, fadeOut: Double = 0.02) {
    let inCount = min(buffer.count, Int(fadeIn * sampleRate))
    for index in 0..<inCount { buffer[index] *= Float(index) / Float(max(inCount, 1)) }
    let outCount = min(buffer.count, Int(fadeOut * sampleRate))
    for offset in 0..<outCount { buffer[buffer.count - 1 - offset] *= Float(offset) / Float(max(outCount, 1)) }
}

func normalize(_ buffer: inout [Float], peak: Float = peakLevel) {
    let current = buffer.map(abs).max() ?? 0
    guard current > 0 else { return }
    let gain = peak / current
    for index in buffer.indices { buffer[index] *= gain }
}

/// Writes mono float samples as AAC in CAF via a temporary PCM file and afconvert.
func write(_ buffer: [Float], to name: String) throws {
    var buffer = buffer
    fadeEdges(&buffer)
    normalize(&buffer)
    let pcmURL = scratch.appending(path: "\(name).pcm.caf")
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
          let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(buffer.count)),
          let channel = pcm.floatChannelData?[0]
    else { throw NSError(domain: "generate-sounds", code: 1) }
    pcm.frameLength = AVAudioFrameCount(buffer.count)
    for (index, value) in buffer.enumerated() { channel[index] = value }
    do {
        let file = try AVAudioFile(forWriting: pcmURL, settings: format.settings)
        try file.write(from: pcm)
    }
    let destination = outputURL.appending(path: "\(name).caf")
    try? FileManager.default.removeItem(at: destination)
    try run("/usr/bin/afconvert", ["-f", "caff", "-d", "aac", "-b", "96000", pcmURL.path, destination.path])
    print(String(format: "%@  %.2f s", destination.lastPathComponent, Double(buffer.count) / sampleRate))
}

func readMono(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    guard let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw NSError(domain: "generate-sounds", code: 2)
    }
    try file.read(into: pcm)
    guard let data = pcm.floatChannelData else { throw NSError(domain: "generate-sounds", code: 3) }
    let channels = Int(pcm.format.channelCount)
    return (0..<Int(pcm.frameLength)).map { frame in
        (0..<channels).reduce(Float(0)) { $0 + data[$1][frame] } / Float(channels)
    }
}

// MARK: - Sounds

/// The Kedro neigh (winner). Real audio from the web app, not a placeholder.
func winner() throws -> [Float] {
    let decoded = scratch.appending(path: "neigh-source.caf")
    try run("/usr/bin/afconvert", ["-f", "caff", "-d", "LEF32@44100", "-c", "1", neighSource.path, decoded.path])
    var audio = try readMono(decoded)
    // Drop the leading silence (the source starts ~1.3 s in).
    let start = audio.firstIndex { abs($0) > 0.01 } ?? 0
    audio = Array(audio[max(0, start - Int(0.02 * sampleRate))...])
    // The design budget is 3 s, faded over the last 0.25 s.
    let limit = Int(3.0 * sampleRate)
    if audio.count > limit { audio = Array(audio[..<limit]) }
    let fade = Int(0.25 * sampleRate)
    for offset in 0..<min(fade, audio.count) {
        audio[audio.count - 1 - offset] *= Float(offset) / Float(fade)
    }
    return audio
}

/// PLACEHOLDER: two hard knuckle raps on wood.
func liveKnock() -> [Float] {
    var output = samples(seconds: 0.42)
    var noise = Noise()
    func rap() -> [Float] {
        var rap = samples(seconds: 0.12)
        for index in rap.indices {
            let t = time(index)
            let body = sin(2 * .pi * 190 * t) * exp(-t * 45) + 0.5 * sin(2 * .pi * 410 * t) * exp(-t * 70)
            rap[index] = Float(body) + noise.next() * Float(exp(-t * 160)) * 0.6
        }
        lowPass(&rap, cutoff: 2_400)
        return rap
    }
    mix(rap(), into: &output, at: 0)
    mix(rap(), into: &output, at: 0.17, gain: 0.95)
    return output
}

/// PLACEHOLDER: a clean whip crack.
func knockLanded() -> [Float] {
    var output = samples(seconds: 0.35)
    var noise = Noise()
    for index in output.indices {
        let t = time(index)
        // A short swish that snaps into a bright crack.
        let swish = t < 0.08 ? noise.next() * Float(t / 0.08) * 0.25 : 0
        let crack = t >= 0.08 ? noise.next() * Float(exp(-(t - 0.08) * 55)) : 0
        output[index] = swish + crack
    }
    highPass(&output, cutoff: 1_800)
    return output
}

/// PLACEHOLDER: a flat shrug of a snare hit.
func knockTied() -> [Float] {
    var output = samples(seconds: 0.3)
    var noise = Noise()
    for index in output.indices {
        let t = time(index)
        let tone = sin(2 * .pi * 185 * t) * exp(-t * 30)
        output[index] = Float(tone) * 0.6 + noise.next() * Float(exp(-t * 18)) * 0.5
    }
    lowPass(&output, cutoff: 5_000)
    return output
}

/// PLACEHOLDER: a crowd groan (detuned voices sliding down).
func knockFailed() -> [Float] {
    let duration = 1.2
    var output = samples(seconds: duration)
    let voices: [(Double, Double)] = [(220, 0.0), (233, 1.3), (196, 2.1), (247, 0.7), (208, 3.3), (185, 2.7)]
    for (base, phase) in voices {
        var phaseAccumulator = phase
        for index in output.indices {
            let t = time(index)
            let pitch = base * (1 - 0.28 * (t / duration)) * (1 + 0.012 * sin(2 * .pi * 5.5 * t + phase))
            phaseAccumulator += 2 * .pi * pitch / sampleRate
            // A few harmonics give it a vocal "uhh".
            let voice = sin(phaseAccumulator) + 0.5 * sin(2 * phaseAccumulator) + 0.3 * sin(3 * phaseAccumulator)
            let envelope = min(1, t / 0.12) * max(0, 1 - pow(t / duration, 2))
            output[index] += Float(voice * envelope)
        }
    }
    lowPass(&output, cutoff: 1_400)
    return output
}

/// PLACEHOLDER: a low, sinister piano sting (minor second over a low octave).
func redKing() -> [Float] {
    let duration = 1.4
    var output = samples(seconds: duration)
    let notes: [Double] = [55, 110, 116.54, 164.81] // A1, A2, B♭2, E3: a tritone and a rub
    for note in notes {
        for index in output.indices {
            let t = time(index)
            var tone = 0.0
            for harmonic in 1...6 {
                let h = Double(harmonic)
                tone += sin(2 * .pi * note * h * t) / (h * h) * exp(-t * (1.6 + h * 0.8))
            }
            output[index] += Float(tone * min(1, t / 0.004))
        }
    }
    return output
}

/// PLACEHOLDER: a card snapped onto the table.
func roundSaved() -> [Float] {
    var output = samples(seconds: 0.12)
    var noise = Noise()
    for index in output.indices {
        let t = time(index)
        output[index] = noise.next() * Float(exp(-t * 90)) + Float(sin(2 * .pi * 900 * t) * exp(-t * 120)) * 0.4
    }
    highPass(&output, cutoff: 700)
    return output
}

/// PLACEHOLDER: a short "ooh" from a crowd.
func tauntReceived() -> [Float] {
    let duration = 0.9
    var output = samples(seconds: duration)
    let voices: [Double] = [262, 277, 294, 247, 311]
    for (offset, base) in voices.enumerated() {
        var phase = Double(offset)
        for index in output.indices {
            let t = time(index)
            // Rises, then falls: "oooOOoo".
            let pitch = base * (1 + 0.18 * sin(.pi * t / duration)) * (1 + 0.01 * sin(2 * .pi * 6 * t + Double(offset)))
            phase += 2 * .pi * pitch / sampleRate
            let voice = sin(phase) + 0.25 * sin(2 * phase)
            output[index] += Float(voice * sin(.pi * t / duration))
        }
    }
    lowPass(&output, cutoff: 900)
    return output
}

/// PLACEHOLDER: a slow, sarcastic three-note trombone ("wah wah wahhh").
func deadLast() -> [Float] {
    var output = samples(seconds: 1.5)
    let notes: [(start: Double, length: Double, pitch: Double, bend: Double)] = [
        (0.0, 0.36, 233.08, 0), (0.4, 0.36, 220.0, 0), (0.8, 0.7, 207.65, -0.06),
    ]
    for note in notes {
        var phase = 0.0
        var tone = samples(seconds: note.length)
        for index in tone.indices {
            let t = time(index)
            let progress = t / note.length
            let pitch = note.pitch * (1 + note.bend * progress) * (1 + 0.015 * sin(2 * .pi * 5 * t) * progress)
            phase += 2 * .pi * pitch / sampleRate
            var wave = 0.0
            for harmonic in 1...7 { wave += sin(Double(harmonic) * phase) / Double(harmonic) }
            let envelope = min(1, t / 0.05) * min(1, (note.length - t) / 0.08)
            tone[index] = Float(wave * envelope)
        }
        lowPass(&tone, cutoff: 1_600)
        mix(tone, into: &output, at: note.start)
    }
    return output
}

/// PLACEHOLDER: a gate bell (inharmonic partials, long decay).
func debut() -> [Float] {
    var output = samples(seconds: 1.4)
    let partials: [(ratio: Double, gain: Double, decay: Double)] = [
        (1.0, 1.0, 2.6), (2.76, 0.5, 4.0), (5.4, 0.25, 6.0), (8.93, 0.12, 9.0),
    ]
    for index in output.indices {
        let t = time(index)
        var tone = 0.0
        for partial in partials {
            tone += partial.gain * sin(2 * .pi * 880 * partial.ratio * t) * exp(-t * partial.decay)
        }
        output[index] = Float(tone * min(1, t / 0.002))
    }
    return output
}

// MARK: - Main

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }

try write(try winner(), to: "classic-winner")
try write(liveKnock(), to: "classic-live-knock")
try write(knockLanded(), to: "classic-knock-landed")
try write(knockTied(), to: "classic-knock-tied")
try write(knockFailed(), to: "classic-knock-failed")
try write(redKing(), to: "classic-red-king")
try write(roundSaved(), to: "classic-round-saved")
try write(tauntReceived(), to: "classic-taunt-received")
try write(deadLast(), to: "classic-dead-last")
try write(debut(), to: "classic-debut")
