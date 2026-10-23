// WAV while it streams in, as intel's /api/speak/stream sends it: a header (usually with an open-ended
// length), then the samples while the speech is still being generated.

import Foundation

public struct WavFormat: Sendable, Equatable {
    public let sampleRate: Int
    public let channels: Int
    public let bitsPerSample: Int

    public init(sampleRate: Int, channels: Int, bitsPerSample: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
    }

    public var bytesPerFrame: Int { channels * bitsPerSample / 8 }
}

public enum WavStreamEvent: Sendable, Equatable {
    /// The samples' format; comes before any samples.
    case format(WavFormat)
    /// Samples (signed little-endian integers), in whole frames.
    case samples(Data)
}

public enum WavStreamError: LocalizedError, Sendable {
    case notWav
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .notWav: return "intel sent something that isn't WAV audio."
        case .unsupported(let what): return "intel sent WAV audio this app can't play (\(what))."
        }
    }
}

/// Reads one WAV stream fed in pieces of any size.
public struct WavStreamReader: Sendable {
    private var buffer = Data()
    private var format: WavFormat?
    private var inSamples = false
    private var samplesLeft: Int?          // nil: until the stream ends
    private static let openEnded: UInt32 = 0xFFFF_FFFF

    public init() {}

    /// What the newly arrived `data` completes.
    public mutating func Feed(_ data: Data) throws -> [WavStreamEvent] {
        buffer.append(data)
        var events: [WavStreamEvent] = []
        if !inSamples {
            guard let header = try ReadHeader() else { return [] }
            events.append(.format(header))
        }
        guard let format else { return events }
        var available = buffer.count
        if let samplesLeft { available = min(available, samplesLeft) }
        available -= available % format.bytesPerFrame
        if available > 0 {
            events.append(.samples(Data(buffer.prefix(available))))
            buffer.removeFirst(available)
            samplesLeft = samplesLeft.map { $0 - available }
        }
        return events
    }

    /// The format, once the header up to the samples has arrived (nil until then).
    private mutating func ReadHeader() throws -> WavFormat? {
        guard buffer.count >= 12 else { return nil }
        guard String(decoding: buffer.prefix(4), as: UTF8.self) == "RIFF",
              String(decoding: buffer.dropFirst(8).prefix(4), as: UTF8.self) == "WAVE" else { throw WavStreamError.notWav }
        var offset = 12
        var found: WavFormat?
        while buffer.count >= offset + 8 {
            let chunk = String(decoding: buffer.dropFirst(offset).prefix(4), as: UTF8.self)
            let size = UInt32(littleEndian: Load(UInt32.self, at: offset + 4))
            if chunk == "data" {
                guard let found else { throw WavStreamError.unsupported("no format before the samples") }
                buffer.removeFirst(offset + 8)
                format = found
                inSamples = true
                samplesLeft = size == 0 || size == Self.openEnded ? nil : Int(size)
                return found
            }
            let padded = Int(size) + Int(size & 1)
            guard buffer.count >= offset + 8 + padded else { return nil }
            if chunk == "fmt " {
                let tag = UInt16(littleEndian: Load(UInt16.self, at: offset + 8))
                let channels = Int(UInt16(littleEndian: Load(UInt16.self, at: offset + 10)))
                let rate = Int(UInt32(littleEndian: Load(UInt32.self, at: offset + 12)))
                let bits = Int(UInt16(littleEndian: Load(UInt16.self, at: offset + 22)))
                guard tag == 1, bits == 16, channels > 0 else {
                    throw WavStreamError.unsupported("format \(tag), \(bits) bits, \(channels) channels")
                }
                found = WavFormat(sampleRate: rate, channels: channels, bitsPerSample: bits)
            }
            offset += 8 + padded
        }
        return nil
    }

    private func Load<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
    }
}
