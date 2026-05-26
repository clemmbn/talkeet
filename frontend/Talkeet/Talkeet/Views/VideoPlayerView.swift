/*
 * VideoPlayerView.swift
 *
 * Purpose: SwiftUI wrapper around AVKit's VideoPlayer for embedding in the editor.
 *
 * Responsibilities:
 *   - Render the video from the provided AVPlayer.
 *   - Show a placeholder when no player is available yet.
 *
 * Constraints:
 *   - Uses AVKit's VideoPlayer directly (native macOS transport controls included).
 *   - The player instance is owned by ProjectViewModel — this view is stateless.
 */

import AVKit
import SwiftUI

struct VideoPlayerView: View {
    /// The player to render. Nil while no file has been loaded yet.
    let player: AVPlayer?

    var body: some View {
        if let player {
            VideoPlayer(player: player)
        } else {
            // Shown before a file is loaded — should rarely be visible in M6.
            ZStack {
                Color.black.opacity(0.05)
                Image(systemName: "film")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    VideoPlayerView(player: nil)
        .frame(width: 640, height: 360)
}
