/*
 * SegmentListView.swift
 *
 * Purpose: Scrollable list of detected video segments with tap-to-seek.
 *
 * Responsibilities:
 *   - Render each segment as a row showing its type, timestamp range, and duration.
 *   - Highlight speech vs silence with distinct colors.
 *   - Call the onSeek callback when a row is tapped so the player can seek.
 *   - Show a loading indicator while analysis is in flight.
 *   - Show an error message if analysis failed.
 *
 * Constraints:
 *   - onSeek is a closure (not a direct AVPlayer reference) to keep the view decoupled.
 *   - Timestamps are displayed in MM:SS.mm format for readability at video timescales.
 */

import SwiftUI

struct SegmentListView: View {
    /// Segments to display.
    let segments: [Segment]
    /// True while the backend is still processing.
    let isAnalyzing: Bool
    /// Non-nil when analysis failed.
    let errorMessage: String?
    /// Called with a segment when the user taps a row.
    let onSeek: (Segment) -> Void

    var body: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()

            if isAnalyzing {
                loadingView
            } else if let error = errorMessage {
                errorView(message: error)
            } else if segments.isEmpty {
                emptyView
            } else {
                segmentRows
            }
        }
    }

    // MARK: - Subviews

    private var listHeader: some View {
        HStack {
            Text("Segments")
                .font(.headline)
            Spacer()
            if !segments.isEmpty {
                Text("\(segments.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Analyzing…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.red)
            Text("Analysis failed")
                .font(.subheadline)
                .bold()
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        Text("No segments yet")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var segmentRows: some View {
        List(segments) { segment in
            SegmentRow(segment: segment)
                .contentShape(Rectangle())
                .onTapGesture { onSeek(segment) }
                .listRowSeparator(.visible)
        }
        .listStyle(.plain)
    }
}

// MARK: - SegmentRow

/// A single row in the segment list showing type badge, timestamps, and duration.
private struct SegmentRow: View {
    let segment: Segment

    var body: some View {
        HStack(spacing: 10) {
            // Type badge
            Text(segment.type == .speech ? "SPEECH" : "SILENCE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(segment.type == .speech ? Color.green : Color.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    (segment.type == .speech ? Color.green : Color.orange).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 4)
                )

            // Timestamp range
            VStack(alignment: .leading, spacing: 2) {
                Text("\(formatTime(segment.start)) → \(formatTime(segment.end))")
                    .font(.system(size: 12, design: .monospaced))
                Text(formatDuration(segment.duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Formats seconds as MM:SS.mm (e.g. 01:23.45).
    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%05.2f", m, s)
    }

    /// Formats a duration in seconds as a compact label (e.g. "1.23s" or "12.3s").
    private func formatDuration(_ seconds: Double) -> String {
        String(format: "%.2fs", seconds)
    }
}

#Preview {
    SegmentListView(
        segments: [
            Segment(start: 0.0, end: 1.5, type: .silence),
            Segment(start: 1.5, end: 4.8, type: .speech),
            Segment(start: 4.8, end: 5.3, type: .silence),
        ],
        isAnalyzing: false,
        errorMessage: nil,
        onSeek: { _ in }
    )
    .frame(width: 260, height: 400)
}
