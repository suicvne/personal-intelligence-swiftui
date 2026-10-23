// Reading an answer aloud: intel turns the text into speech (POST /api/speak, using `[voice]` in its
// config) and this plays it. Generating the speech can take a while; Stop also cancels that.

import AVFoundation
import IntelKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SpeechPlayer: NSObject, AVAudioPlayerDelegate {
    enum State { case idle, preparing, playing }

    private(set) var state = State.idle
    /// Why the last text couldn't be read aloud, until the next try.
    private(set) var failure: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var preparing: Task<Void, Never>?

    /// Read `text` aloud, instead of anything being read now: in the current persona's voice, or the one
    /// `voice` describes.
    func Speak(_ text: String, voice: String? = nil, with client: IntelClient) {
        Stop()
        failure = nil
        state = .preparing
        preparing = Task {
            do {
                let audio = try await client.Speech(text: text, voice: voice)
                try Task.checkCancellation()
                let player = try AVAudioPlayer(data: audio)
                player.delegate = self
                self.player = player
                state = player.play() ? .playing : .idle
            } catch {
                if Task.isCancelled { return }      // stopped: not a failure
                failure = error.localizedDescription
                state = .idle
            }
        }
    }

    func Stop() {
        preparing?.cancel()
        preparing = nil
        player?.stop()
        player = nil
        state = .idle
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            guard let current = self.player, ObjectIdentifier(current) == finished else { return }
            self.player = nil
            self.state = .idle
        }
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
