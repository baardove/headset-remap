import Foundation

enum TestTone {
    /// A quiet, audible pair of tones each second. No microphone/audio files required.
    static func wav() -> Data {
        let rate = 22_050
        var pcm = Data()
        for i in 0..<rate {
            let t = Double(i) / Double(rate)
            let local = t.truncatingRemainder(dividingBy: 0.5)
            let envelope = local < 0.12 ? sin(.pi * local / 0.12) : 0
            let value = Int16(sin(2 * .pi * 440 * t) * envelope * 1200)
            append(value, to: &pcm)
        }
        var data = Data("RIFF".utf8)
        append(UInt32(36 + pcm.count), to: &data)
        data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data) // PCM
        append(UInt16(1), to: &data) // mono
        append(UInt32(rate), to: &data)
        append(UInt32(rate * 2), to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        data.append(Data("data".utf8))
        append(UInt32(pcm.count), to: &data)
        data.append(pcm)
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
