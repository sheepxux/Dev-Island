#!/usr/bin/env swift

import Foundation

private let sampleRate = 44_100

private struct Note {
    let start: Double
    let duration: Double
    let frequency: Double
    let gain: Double
}

private struct Cue {
    let filename: String
    let duration: Double
    let notes: [Note]
}

private let cues = [
    Cue(
        filename: "DevIsland-Attention.wav",
        duration: 0.34,
        notes: [
            Note(start: 0.000, duration: 0.145, frequency: 880.00, gain: 0.31),
            Note(start: 0.105, duration: 0.205, frequency: 1_318.51, gain: 0.27),
            Note(start: 0.000, duration: 0.280, frequency: 440.00, gain: 0.065),
        ]
    ),
    Cue(
        filename: "DevIsland-Failure.wav",
        duration: 0.37,
        notes: [
            Note(start: 0.000, duration: 0.155, frequency: 783.99, gain: 0.29),
            Note(start: 0.115, duration: 0.220, frequency: 523.25, gain: 0.32),
            Note(start: 0.115, duration: 0.220, frequency: 261.63, gain: 0.055),
        ]
    ),
    Cue(
        filename: "DevIsland-Completed.wav",
        duration: 0.42,
        notes: [
            Note(start: 0.000, duration: 0.125, frequency: 659.25, gain: 0.21),
            Note(start: 0.085, duration: 0.145, frequency: 783.99, gain: 0.21),
            Note(start: 0.175, duration: 0.205, frequency: 987.77, gain: 0.24),
            Note(start: 0.175, duration: 0.205, frequency: 493.88, gain: 0.045),
        ]
    ),
]

private func envelope(at localTime: Double, duration: Double) -> Double {
    let attack = min(0.010, duration * 0.15)
    let release = min(0.085, duration * 0.42)
    if localTime < attack { return localTime / attack }
    if localTime > duration - release {
        return max(0, (duration - localTime) / release)
    }
    let decayPosition = (localTime - attack) / max(0.001, duration - attack - release)
    return 1.0 - (0.30 * min(max(decayPosition, 0), 1))
}

/// A rounded pulse keeps the cue recognizable as digital without the brittle
/// top end of a raw square wave.
private func roundedPulse(phase: Double) -> Double {
    (sin(phase) * 0.82) + (sin(phase * 3) * 0.13) + (sin(phase * 5) * 0.05)
}

private func renderedSamples(for cue: Cue) -> [Int16] {
    let sampleCount = Int((cue.duration * Double(sampleRate)).rounded(.up))
    return (0..<sampleCount).map { index in
        let time = Double(index) / Double(sampleRate)
        var sample = 0.0

        for note in cue.notes where time >= note.start && time < note.start + note.duration {
            let localTime = time - note.start
            let phase = 2.0 * Double.pi * note.frequency * localTime
            sample += roundedPulse(phase: phase)
                * envelope(at: localTime, duration: note.duration)
                * note.gain
        }

        // A tiny global fade protects both ends even if a note starts at zero.
        let edge = min(time / 0.004, (cue.duration - time) / 0.012, 1.0)
        let clamped = min(max(sample * max(edge, 0), -0.92), 0.92)
        return Int16((clamped * Double(Int16.max)).rounded())
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private func waveData(samples: [Int16]) -> Data {
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign = channels * (bitsPerSample / 8)
    let payloadSize = UInt32(samples.count * MemoryLayout<Int16>.size)

    var data = Data()
    data.append(contentsOf: "RIFF".utf8)
    data.appendLittleEndian(UInt32(36) + payloadSize)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    data.appendLittleEndian(UInt32(16))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(channels)
    data.appendLittleEndian(UInt32(sampleRate))
    data.appendLittleEndian(byteRate)
    data.appendLittleEndian(blockAlign)
    data.appendLittleEndian(bitsPerSample)
    data.append(contentsOf: "data".utf8)
    data.appendLittleEndian(payloadSize)
    for sample in samples { data.appendLittleEndian(sample) }
    return data
}

let scriptURL = URL(fileURLWithPath: #filePath)
let repositoryRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputDirectory = ProcessInfo.processInfo.environment["OUTPUT_DIR"].map {
    URL(fileURLWithPath: $0, isDirectory: true)
} ?? repositoryRoot.appendingPathComponent("IslandApp/Resources", isDirectory: true)

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

for cue in cues {
    let url = outputDirectory.appendingPathComponent(cue.filename)
    try waveData(samples: renderedSamples(for: cue)).write(to: url, options: .atomic)
    print("Rendered \(cue.filename)")
}
