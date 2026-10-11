import AVFoundation
import Foundation

/// Plays near-silent audio so iOS keeps Locus runnable (and able to accept
/// TCP) while the user is in Settings › Developer Mode.
final class SilentAudioKeepAlive {
    static let preferenceKey = "locus.pairingAudioKeepAlive"
    private var player: AVAudioPlayer?
    private var wasActive = false
    private var activatedSession = false

    func start() {
        guard UserDefaults.standard.bool(forKey: Self.preferenceKey), !wasActive else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            activatedSession = true

            // 0.1s of near-silence, looped.
            let url = try Self.writeSilentWAV()
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.01
            p.prepareToPlay()
            guard p.play() else { stop(); return }
            player = p
            wasActive = true
            NSLog("[Locus] silent audio keep-alive started")
        } catch {
            stop()
            NSLog("[Locus] silent audio keep-alive failed: %@", error.localizedDescription)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        wasActive = false
        if activatedSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            activatedSession = false
        }
    }

    private static func writeSilentWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("locus-silence.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let sampleRate: Int = 8000
        let durationSamples = sampleRate / 10 // 0.1s
        var data = Data()

        func appendUInt32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        let dataSize = UInt32(durationSamples * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(1) // mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(dataSize)
        data.append(Data(count: Int(dataSize))) // zeros = silence

        try data.write(to: url, options: .atomic)
        return url
    }
}
