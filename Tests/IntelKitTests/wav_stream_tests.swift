// Reading the WAV stream /api/speak/stream sends, in pieces of any size.

import Foundation
import Testing
@testable import IntelKit

private func Header(rate: UInt32 = 24_000, channels: UInt16 = 1, bits: UInt16 = 16, tag: UInt16 = 1,
                    dataBytes: UInt32 = 0xFFFF_FFFF) -> Data {
    var data = Data("RIFF".utf8)
    func Append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    Append(UInt32(0xFFFF_FFFF))
    data.append(contentsOf: Data("WAVEfmt ".utf8))
    Append(UInt32(16)); Append(tag); Append(channels); Append(rate)
    Append(rate * UInt32(channels * bits / 8)); Append(UInt16(channels * bits / 8)); Append(bits)
    data.append(contentsOf: Data("data".utf8))
    Append(dataBytes)
    return data
}

private func Read(_ stream: Data, inPiecesOf size: Int) throws -> (formats: [WavFormat], samples: Data) {
    var reader = WavStreamReader()
    var formats: [WavFormat] = []
    var samples = Data()
    var start = 0
    while start < stream.count {
        for event in try reader.Feed(stream.subdata(in: start..<min(start + size, stream.count))) {
            switch event {
            case .format(let format): formats.append(format)
            case .samples(let piece):
                #expect(piece.count % 2 == 0)
                samples.append(piece)
            }
        }
        start += size
    }
    return (formats, samples)
}

@Test func ReadsAnOpenEndedWavStreamInPiecesOfAnySize() throws {
    let samples = Data((0..<4_000).map { UInt8($0 % 251) })
    for size in [1, 3, 44, 45, 1_000, 10_000] {
        let read = try Read(Header() + samples, inPiecesOf: size)
        #expect(read.formats == [WavFormat(sampleRate: 24_000, channels: 1, bitsPerSample: 16)], "pieces of \(size)")
        #expect(read.samples == samples, "pieces of \(size)")
    }
}

@Test func StopsAtTheEndOfAWavWithALength() throws {
    let read = try Read(Header(dataBytes: 6) + Data([1, 2, 3, 4, 5, 6]) + Data("LIST".utf8), inPiecesOf: 5)
    #expect(read.samples == Data([1, 2, 3, 4, 5, 6]))
}

@Test func RefusesWhatItCantPlay() {
    var reader = WavStreamReader()
    #expect(throws: WavStreamError.self) { try reader.Feed(Data("{\"error\": \"nope\"}".utf8)) }
    var floats = WavStreamReader()
    #expect(throws: WavStreamError.self) { try floats.Feed(Header(bits: 32, tag: 3)) }
}
