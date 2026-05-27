/*
 * EditorView.swift
 *
 * Purpose: Full editor layout shown after a video file has been loaded.
 *
 * Responsibilities:
 *   - Arrange VideoPlayerView + WaveformView (main area) and SegmentListView (sidebar) side by side.
 *   - Wire segment tap → ProjectViewModel.seekToSegment(_:).
 *   - Provide a "Close" button to return to the drop zone.
 *
 * Constraints:
 *   - ProjectViewModel is passed in (not read from environment) so EditorView
 *     remains reusable and previewable in isolation.
 *   - The split is fixed-ratio (no draggable divider) until M7 adds interactive scrubbing.
 */

import SwiftUI

struct EditorView: View {
    /// All editing state for the current session.
    @Bindable var viewModel: ProjectViewModel
    /// Called when the user wants to close the current file and return to the drop zone.
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Main area: video player + waveform timeline
            VStack(spacing: 0) {
                toolbar
                Divider()
                VideoPlayerView(player: viewModel.player)
                Divider()
                WaveformView(
                    samples: viewModel.waveformSamples,
                    segments: viewModel.segments
                )
            }

            Divider()

            // Sidebar: segment list
            SegmentListView(
                segments: viewModel.segments,
                isAnalyzing: viewModel.isAnalyzing,
                errorMessage: viewModel.errorMessage,
                onSeek: { viewModel.seekToSegment($0) }
            )
            .frame(width: 260)
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                Label("Close", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)

            if let name = viewModel.videoURL?.lastPathComponent {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    let vm = ProjectViewModel()
    EditorView(viewModel: vm, onClose: {})
}
