import AVFoundation
import Observation

/// A quiet procedural mechanical pulse. Audio data is synthesized before playback;
/// no SwiftUI or mutable state is accessed from a realtime render callback.
@Observable @MainActor
final class MechanicalSound {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var configured = false
    private var lastBucket = -1
    private(set) var error: String?

    func update(rate: Double, enabled: Bool) {
        guard enabled else { stop(); return }
        let bucket = max(1, min(10, Int(rate.rounded())))
        guard bucket != lastBucket || !player.isPlaying else { return }
        do {
            if !configured {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
                if !engine.attachedNodes.contains(player) { engine.attach(player) }
                try engine.connectNode(player, to: engine.mainMixerNode, format: format)
                configured = true
            }
            if !engine.isRunning { try engine.start() }
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            let count = AVAudioFrameCount(44_100)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
                  let data = buffer.floatChannelData?[0] else { return }
            buffer.frameLength = count
            let pulses = Double(bucket)
            for i in 0..<Int(count) {
                let t = Double(i) / 44_100
                let beat = (t * pulses).truncatingRemainder(dividingBy: 1)
                let envelope = exp(-beat * 30) * sin(.pi * min(1, beat * 60))
                let carrier = sin(2 * .pi * (75 + pulses * 8) * t)
                // Endpoint fades prevent a click at the loop boundary.
                let edge = min(1, min(t, 1 - t) * 500)
                data[i] = Float(0.10 * carrier * envelope * edge)
            }
            player.stop(); player.scheduleBuffer(buffer, at: nil, options: [.loops]); try player.playAudio()
            lastBucket = bucket; error = nil
        } catch {
            self.error = error.localizedDescription; stop()
        }
    }

    func stop() {
        if player.isPlaying { player.stop() }
        if engine.isRunning { engine.pause() }
        lastBucket = -1
    }
}
