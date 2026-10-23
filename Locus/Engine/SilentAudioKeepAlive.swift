import AVFoundation
import Foundation

/// Plays near-silent audio so iOS keeps location runnable (and able to accept
/// TCP) while the user is in Settings › Developer Mode.
@MainActor
final class SilentAudioKeepAlive {
    enum Issue { case interrupted, unavailable }
    static let preferenceKey = "locus.pairingAudioKeepAlive"
    var onIssue: ((Issue?) -> Void)?
    private var player: AVAudioPlayer?
    private var activatedSession = false
    private var policy = PairingAudioPolicy()
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard let token = policy.begin(enabled: UserDefaults.standard.bool(forKey: Self.preferenceKey)) else { return }
        observeAudioSession(token: token)
        play(token: token)
    }

    private func play(token: Int) {
        guard policy.accepts(token) else { return }
        guard UserDefaults.standard.bool(forKey: Self.preferenceKey) else { stop(); return }
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
            guard p.play() else { releaseAudio(); onIssue?(.unavailable); return }
            player = p
            onIssue?(nil)
        } catch {
            releaseAudio()
            onIssue?(.unavailable)
        }
    }

    func stop() {
        policy.stop()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        releaseAudio()
        onIssue?(nil)
    }

    private func releaseAudio() {
        player?.stop()
        player = nil
        if activatedSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            activatedSession = false
        }
    }

    private func observeAudioSession(token: Int) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] notification in
            let typeValue = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let optionsValue = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor in
                guard let self, let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
                if type == .began {
                    guard self.policy.interruptionBegan(token: token) else { return }
                    self.player?.pause()
                    self.onIssue?(.interrupted)
                } else {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    guard self.policy.interruptionEnded(token: token, shouldResume: options.contains(.shouldResume)) else { return }
                    self.releaseAudio()
                    self.play(token: token)
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.policy.mayRecoverAfterReset(token: token) else { return }
                self.player = nil
                self.activatedSession = false
                self.play(token: token)
            }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.policy.accepts(token),
                      !UserDefaults.standard.bool(forKey: Self.preferenceKey) else { return }
                self.stop()
            }
        })
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
