import AppKit
import AVKit
import SwiftUI

struct TimelineVideoPlayer: NSViewRepresentable {
    let videoPlayer: AVPlayer

    func makeNSView(context _: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.allowsPictureInPicturePlayback = true
        playerView.showsFullScreenToggleButton = true
        playerView.showsSharingServiceButton = true

        playerView.player = videoPlayer

        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context _: Context) {
        playerView.player = videoPlayer
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    class Coordinator {}
}
