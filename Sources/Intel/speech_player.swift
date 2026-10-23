// Reading an answer aloud: intel turns the text into speech (POST /api/speak/stream, using `[voice]` in its
// config) and this plays it while it is still being generated: the first words play about a second and a
// half after asking. Stop also stops the speech being generated.

import AVFoundation
import IntelKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SpeechPlayer {
    enum State { case idle, preparing, playing }

    private(set) var state = State.idle
    /// Why the last text couldn't be read aloud, until the next try.
    private(set) var failure: String?
    /// What is being (or was last) read aloud; Stop forgets it.
    @ObservationIgnored private var text: String?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var node: AVAudioPlayerNode?
    @ObservationIgnored private var streaming: Task<Void, Never>?
    @ObservationIgnored private var unplayed = 0        // buffers scheduled and not played yet
    @ObservationIgnored private var received = false    // the whole speech has arrived
    @ObservationIgnored private var generation = 0      // which Speak a buffer's callback belongs to

    /// Read `text` aloud, in the current persona's voice or the one `voice` describes, instead of anything
    /// being read now. Text already being read (or read since the last Stop) is not read again, unless `again`.
    func Speak(_ text: String, voice: String? = nil, again: Bool = false, with client: IntelClient) {
        if text == self.text && !again { return }
        Stop()
        self.text = text
        failure = nil
        state = .preparing
        let current = generation
        streaming = Task {
            do {
                var reader = WavStreamReader()
                var format: AVAudioFormat?
                for try await piece in client.SpeechStream(text: text, voice: voice) {
                    for event in try reader.Feed(piece) {
                        switch event {
                        case .format(let wav): format = try Start(wav)
                        case .samples(let samples): if let format { Schedule(samples, format, current) }
                        }
                    }
                }
                try Task.checkCancellation()
                received = true
                FinishIfPlayed()
            } catch {
                if Task.isCancelled || current != generation { return }      // stopped: not a failure
                Release()
                failure = error.localizedDescription
            }
        }
    }

    func Stop() {
        streaming?.cancel()
        streaming = nil
        Release()
        text = nil
    }

    /// Stop playing and let go of the audio engine; anything still scheduled is dropped.
    private func Release() {
        generation += 1
        node?.stop()
        engine?.stop()
        node = nil
        engine = nil
        unplayed = 0
        received = false
        state = .idle
    }

    private func Start(_ wav: WavFormat) throws -> AVAudioFormat {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(wav.sampleRate),
                                         channels: AVAudioChannelCount(wav.channels)) else {
            throw WavStreamError.unsupported("\(wav.sampleRate) Hz, \(wav.channels) channels")
        }
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
        node.play()
        self.engine = engine
        self.node = node
        state = .playing
        return format
    }

    /// Queue 16-bit samples to play after those already queued. One that comes late plays when it comes.
    private func Schedule(_ samples: Data, _ format: AVAudioFormat, _ current: Int) {
        let channels = Int(format.channelCount)
        let frames = samples.count / (2 * channels)
        guard frames > 0, let node,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let output = buffer.floatChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        samples.withUnsafeBytes { raw in
            for frame in 0..<frames {
                for channel in 0..<channels {
                    let offset = (frame * channels + channel) * 2
                    output[channel][frame] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: offset,
                                                                                            as: Int16.self))) / 32768
                }
            }
        }
        unplayed += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.Played(current) }
        }
    }

    private func Played(_ buffer: Int) {
        guard buffer == generation else { return }
        unplayed -= 1
        FinishIfPlayed()
    }

    private func FinishIfPlayed() {
        if received && unplayed == 0 { Release() }
    }
}

/// A button that reads something aloud. While it does, it shows progress (generating the speech can take a
/// while) and then Stop; a failure is shown below it.
struct SpeechButton: View {
    let title: String
    let player: SpeechPlayer
    let speak: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                switch player.state {
                case .idle:
                    Button(title, systemImage: "speaker.wave.2", action: speak)
                case .preparing:
                    ProgressView().controlSize(.small)
                    Text("Preparing the voice…").foregroundStyle(.secondary)
                    Button("Cancel") { player.Stop() }
                case .playing:
                    Button("Stop", systemImage: "stop.fill") { player.Stop() }
                }
            }
            .font(.callout)
            .buttonStyle(.borderless)
            if let failure = player.failure {
                Text(failure).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
