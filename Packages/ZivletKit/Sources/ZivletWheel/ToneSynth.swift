import Foundation

/// The highlight tick, synthesized in code (no bundled sample): a short sine burst with a 1 ms attack, a fast
/// exponential decay and a 1 ms fade-out, as 16-bit mono PCM in a WAV container.
public enum ToneSynth {
    public static func wav(
        frequency: Double = 1_318.5, duration: Duration = .milliseconds(24), sampleRate: Int = 48_000,
        amplitude: Double = 0.18
    ) -> Data {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let count = Int(seconds * Double(sampleRate))
        let tail = Double(sampleRate) / 1_000
        let samples = (0..<count).map { index -> Int16 in
            let t = Double(index) / Double(sampleRate)
            let envelope = min(1, t / 0.001) * exp(-t / 0.006) * min(1, Double(count - 1 - index) / tail)
            return Int16((sin(2 * .pi * frequency * t) * amplitude * envelope * 32_767).rounded())
        }
        return header(sampleCount: count, sampleRate: sampleRate)
            + samples.reduce(into: Data()) { data, sample in
                withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
            }
    }

    private static func header(sampleCount: Int, sampleRate: Int) -> Data {
        let dataSize = UInt32(sampleCount * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))  // PCM
        append(UInt16(1))  // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))  // byte rate
        append(UInt16(2))  // block align
        append(UInt16(16))  // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)
        return data
    }
}
