import AVFoundation
import Foundation

/// 控えめなニャー音をプロシージャル合成で鳴らす。
/// 音声アセットをバンドルしない理由: build-app.sh は実行バイナリしか .app にコピーせず、
/// SPM リソースバンドルは手組み .app で Bundle.module が壊れる足枷になるため。
///
/// エンジンはオンデマンド起動（鳴く時に start → 再生後に stop）。常時起動だと
/// 出力デバイス変更（AirPods 接続等）で構成変更通知への対応が必要になるが、
/// 都度起動なら常に現在のデバイスで初期化されるので考えなくてよい。CPU もゼロに保てる。
final class MeowPlayer {
    static let shared = MeowPlayer()

    /// ミュート設定（メニューバー右クリックで切替）。UserDefaults で再起動後も維持。
    var isMuted: Bool {
        get { UserDefaults.standard.bool(forKey: Self.mutedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.mutedKey) }
    }
    private static let mutedKey = "meowMuted"

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var lastMeow = Date.distantPast
    private var stopTimer: Timer?

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: Self.format)
        buffer = Self.makeMeowBuffer()
    }

    /// ニャー（1回）。複数セッションが同時に waiting になっても合唱しないよう
    /// 2秒のグローバルデバウンスをかける。
    func meow() {
        guard !isMuted, let buffer = buffer else { return }
        let now = Date()
        guard now.timeIntervalSince(lastMeow) > 2 else { return }
        lastMeow = now

        if !engine.isRunning {
            do { try engine.start() } catch { return }   // 出力デバイス不在等。鳴らさないだけ。
        }
        player.scheduleBuffer(buffer, at: nil)
        player.play()

        // 再生終了から余裕を見てエンジンを止める（次の meow が来たら先送り）。
        stopTimer?.invalidate()
        stopTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.player.stop()
            self.engine.stop()
        }
    }

    // MARK: - 合成

    private static let sampleRate = 44_100.0
    private static let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    /// 0.35秒の「ニャッ」: 720→480Hz スイープ + ビブラート + 減衰倍音、ゲイン 0.15。
    private static func makeMeowBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.35
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        let samples = buf.floatChannelData![0]

        var phase = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate          // 経過秒
            let progress = t / duration             // 0...1
            // 基本周波数: 720→480Hz + 6Hz ビブラート（±3%）。
            let f0 = 720.0 - 240.0 * progress
            let vibrato = 1.0 + 0.03 * sin(2 * .pi * 6 * t)
            phase += 2 * .pi * f0 * vibrato / sampleRate
            // 倍音は高次ほど早く減衰させて「鳴き声」っぽい角を取る。
            let h1 = sin(phase)
            let h2 = 0.45 * sin(phase * 2) * (1 - progress)
            let h3 = 0.20 * sin(phase * 3) * (1 - progress) * (1 - progress)
            // エンベロープ: 30ms アタック → 指数減衰。
            let attack = min(1.0, t / 0.03)
            let decay = exp(-3.2 * progress)
            samples[i] = Float((h1 + h2 + h3) * attack * decay * 0.15)
        }
        return buf
    }
}
