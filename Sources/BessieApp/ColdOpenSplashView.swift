import AVFoundation
import AppKit
import SwiftUI

struct ColdOpenSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let bootstrapSettled: Bool
    /// When false, skip AVPlayer and show the native "joining the herd" loader.
    /// Ordinary completed launches use the loader; first-run / Run Setup Again play once.
    let playsVideo: Bool
    let finished: () -> Void
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var playbackFinished = false

    var body: some View {
        ZStack {
            Color(.sRGB, white: 14 / 255, opacity: 1).ignoresSafeArea()
            if !playsVideo || reduceMotion || failed || player == nil {
                VStack(spacing: 14) {
                    BessiePhosphorCow(size: 64)
                        .foregroundStyle(Color.white)
                    Text("Bessie")
                        .font(.system(size: 26, weight: .medium))
                        .tracking(-0.52)
                        .foregroundStyle(Color.white)
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("joining the herd")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.gray)
                    }
                    .padding(.top, 6)
                }
            } else if let player {
                ColdOpenPlayerView(player: player)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .clipped()
            }
        }
        .background(Color(.sRGB, white: 14 / 255, opacity: 1))
        .bessieOnboardingWindowTitle(BessieOnboardingWindowChrome.splashTitle)
        .preferredColorScheme(.dark)
        .onAppear {
            let isPlaying = prepare()
            // The corrected clip is 7.105 seconds. This safety deadline covers
            // a missed AVPlayer completion notification without cutting off a
            // player that started late or stalled.
            let safetyDelay = isPlaying ? 15.0 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + safetyDelay) {
                guard isPlaying else {
                    playbackDidEnd()
                    return
                }
                guard let item = player?.currentItem,
                      item.duration.isNumeric,
                      (player?.currentTime().seconds ?? 0) >= item.duration.seconds - 0.15
                else {
                    playbackDidFail()
                    return
                }
                playbackDidEnd()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  item === player?.currentItem else { return }
            playbackDidEnd()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  item === player?.currentItem else { return }
            playbackDidFail()
        }
        .onChange(of: bootstrapSettled) { _, _ in finishIfReady() }
    }

    private func prepare() -> Bool {
        guard playsVideo,
              !reduceMotion,
              ProcessInfo.processInfo.environment["BESSIE_COLD_OPEN_FALLBACK"] != "1",
              ProcessInfo.processInfo.environment["BESSIE_COLD_OPEN_FORCE_FALLBACK"] != "1"
        else { return false }
        guard let url = BessieResources.url(forResource: "bessie-cold-open", withExtension: "mp4") else {
            failed = true
            return false
        }
        let player = AVPlayer(url: url)
        player.isMuted = true
        self.player = player
        // First-run / Run Setup Again always play at 1×. Ordinary launches never reach here.
        player.playImmediately(atRate: 1)
        return true
    }

    private func playbackDidEnd() {
        playbackFinished = true
        finishIfReady()
    }

    private func playbackDidFail() {
        failed = true
        playbackDidEnd()
    }

    private func finishIfReady() {
        guard ProcessInfo.processInfo.environment["BESSIE_COLD_OPEN_HOLD"] != "1" else { return }
        guard playbackFinished, bootstrapSettled else { return }
        finished()
    }
}

private struct ColdOpenPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> ColdOpenLayerView {
        let view = ColdOpenLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: ColdOpenLayerView, context: Context) {
        view.playerLayer.player = player
    }
}

private final class ColdOpenLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        layer = playerLayer
    }

    required init?(coder: NSCoder) { nil }
}
