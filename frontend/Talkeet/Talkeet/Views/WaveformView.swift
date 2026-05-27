/*
 * WaveformView.swift
 *
 * Purpose: Renders a scrollable audio waveform with color-coded segment regions.
 *
 * Responsibilities:
 *   - Draw normalized RMS amplitude buckets as vertical bars in a SwiftUI Canvas.
 *   - Color-code background regions by segment type:
 *       speech  → clear (neutral, no tint)
 *       silence → red tint (highlighted for removal)
 *   - Show a placeholder when samples have not yet loaded.
 *
 * Constraints:
 *   - `duration` is derived from segments.last?.end so no extra state is needed.
 *   - Canvas redraws automatically when samples or segments change (both are @Observable state).
 *   - Bar width is clamped to at least 1 pt so individual bars remain visible at low zoom.
 */

import SwiftUI

// MARK: - WaveformView

struct WaveformView: View {
    /// Normalized amplitude buckets in [0.0, 1.0]; index maps to time via (i / count) * duration.
    let samples: [Double]
    /// Segment boundaries used to color-code background regions.
    let segments: [Segment]

    var body: some View {
        Group {
            if samples.isEmpty {
                // Shown while waveform is loading or if the fetch failed.
                placeholderView
            } else {
                waveformCanvas
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Waveform canvas

    private var waveformCanvas: some View {
        Canvas { context, size in
            let duration = segments.last?.end ?? 0

            // Pass 1: draw colored segment background regions.
            if duration > 0 {
                for segment in segments where segment.type == .silence {
                    let xStart = CGFloat(segment.start / duration) * size.width
                    let xEnd   = CGFloat(segment.end   / duration) * size.width
                    let rect   = CGRect(x: xStart, y: 0, width: xEnd - xStart, height: size.height)
                    // Silence regions get a red tint to mark them for removal.
                    context.fill(Path(rect), with: .color(.red.opacity(0.15)))
                }
            }

            // Pass 2: draw waveform bars, symmetric around the vertical center.
            let count   = samples.count
            let barW    = max(size.width / CGFloat(count), 1.0)
            let midY    = size.height / 2

            for (i, sample) in samples.enumerated() {
                let x          = CGFloat(i) * barW
                let halfHeight = CGFloat(sample) * midY
                // Leave a 0.5 pt gap between bars when there is room; skip gap when bars are 1 pt wide.
                let drawW  = barW > 1 ? barW - 0.5 : barW
                let rect   = CGRect(x: x, y: midY - halfHeight, width: drawW, height: halfHeight * 2)
                context.fill(Path(rect), with: .color(.primary.opacity(0.65)))
            }
        }
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        HStack {
            Spacer()
            Text("Loading waveform…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("With samples") {
    let samples = (0..<200).map { i -> Double in
        let t = Double(i) / 200.0
        // Fake waveform: sine wave with some variation.
        return abs(sin(t * .pi * 20)) * 0.5 + Double.random(in: 0...0.3)
    }
    let segments: [Segment] = [
        Segment(start: 0.0,  end: 2.0,  type: .silence),
        Segment(start: 2.0,  end: 7.0,  type: .speech),
        Segment(start: 7.0,  end: 8.5,  type: .silence),
        Segment(start: 8.5,  end: 12.0, type: .speech),
        Segment(start: 12.0, end: 13.0, type: .silence),
    ]
    return WaveformView(samples: samples, segments: segments)
        .padding()
}

#Preview("Empty (loading)") {
    WaveformView(samples: [], segments: [])
        .padding()
}
