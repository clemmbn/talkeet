/*
 * WaveformView.swift
 *
 * Purpose: Renders a scrollable audio waveform with color-coded segment regions,
 *          a real-time playhead, and tap/drag-to-seek interaction.
 *
 * Responsibilities:
 *   - Draw normalized RMS amplitude buckets as vertical bars in a SwiftUI Canvas.
 *   - Color-code background regions by segment type:
 *       speech  → clear (neutral, no tint)
 *       silence → red tint (highlighted for removal)
 *   - Draw a playhead line at the currentTime position (updated at ~30 fps).
 *   - Translate tap/drag x-position to a time value and call onSeek so the
 *     AVPlayer follows user scrubbing.
 *   - Show a placeholder when samples have not yet loaded.
 *
 * Constraints:
 *   - `duration` is derived from segments.last?.end so no extra state is needed.
 *   - Canvas redraws automatically when samples, segments, or currentTime change.
 *   - Bar width is clamped to at least 1 pt so individual bars remain visible at low zoom.
 *   - GeometryReader is used to expose the canvas width to the DragGesture handler
 *     without additional @State — the value is read from the proxy at gesture time.
 */

import SwiftUI

// MARK: - WaveformView

struct WaveformView: View {
    /// Normalized amplitude buckets in [0.0, 1.0]; index maps to time via (i / count) * duration.
    let samples: [Double]
    /// Segment boundaries used to color-code background regions.
    let segments: [Segment]
    /// Current playback position in seconds; drives the playhead line position.
    let currentTime: Double
    /// Called when the user taps or drags on the waveform to seek to a time in seconds.
    let onSeek: (Double) -> Void

    /// Current zoom multiplier; 1.0 = fit-to-width. Clamped to [1.0, 50.0].
    @State private var zoomScale: CGFloat = 1.0
    /// Zoom captured at gesture start so delta magnification accumulates correctly.
    @State private var gestureBaseZoom: CGFloat = 1.0

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
        // GeometryReader lets the DragGesture handler convert x-position → time
        // without needing an extra @State for the view width.
        GeometryReader { geo in
            let duration = segments.last?.end ?? 0

            Canvas { context, size in
                drawSegmentBackgrounds(context: context, size: size, duration: duration)
                drawWaveformBars(context: context, size: size)
                drawPlayhead(context: context, size: size, duration: duration)
            }
            .gesture(
                // minimumDistance: 0 so a plain tap (zero drag) is also handled.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0, geo.size.width > 0 else { return }
                        let fraction = value.location.x / geo.size.width
                        let time = Double(fraction) * duration
                        // Clamp to [0, duration] so dragging past the edges is safe.
                        onSeek(max(0, min(time, duration)))
                    }
            )
        }
    }

    // MARK: - Canvas drawing

    /// Draws red-tinted background regions for silence segments.
    /// - Parameters:
    ///   - context: The active Canvas graphics context.
    ///   - size: Full canvas size in points.
    ///   - duration: Total audio duration in seconds; used to map time → x.
    private func drawSegmentBackgrounds(context: GraphicsContext, size: CGSize, duration: Double) {
        guard duration > 0 else { return }
        for segment in segments where segment.type == .silence {
            let xStart = CGFloat(segment.start / duration) * size.width
            let xEnd   = CGFloat(segment.end   / duration) * size.width
            let rect   = CGRect(x: xStart, y: 0, width: xEnd - xStart, height: size.height)
            context.fill(Path(rect), with: .color(.red.opacity(0.15)))
        }
    }

    /// Draws symmetric vertical amplitude bars from the samples array.
    /// - Parameters:
    ///   - context: The active Canvas graphics context.
    ///   - size: Full canvas size in points.
    private func drawWaveformBars(context: GraphicsContext, size: CGSize) {
        let count = samples.count
        // barW ≥ 1 pt so bars remain visible even with many samples at low zoom.
        let barW  = max(size.width / CGFloat(count), 1.0)
        let midY  = size.height / 2

        for (i, sample) in samples.enumerated() {
            let x          = CGFloat(i) * barW
            let halfHeight = CGFloat(sample) * midY
            // 0.5 pt gap only when bars are wide enough to show it.
            let drawW      = barW > 1 ? barW - 0.5 : barW
            let rect       = CGRect(x: x, y: midY - halfHeight, width: drawW, height: halfHeight * 2)
            context.fill(Path(rect), with: .color(.primary.opacity(0.65)))
        }
    }

    /// Draws the playhead line at the current playback position on top of bars.
    /// - Parameters:
    ///   - context: The active Canvas graphics context.
    ///   - size: Full canvas size in points.
    ///   - duration: Total audio duration in seconds.
    private func drawPlayhead(context: GraphicsContext, size: CGSize, duration: Double) {
        guard duration > 0 else { return }
        let x = CGFloat(currentTime / duration) * size.width
        var path = Path()
        path.move(to:    CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1.5))
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
    return WaveformView(samples: samples, segments: segments, currentTime: 4.0, onSeek: { _ in })
        .padding()
}

#Preview("Empty (loading)") {
    WaveformView(samples: [], segments: [], currentTime: 0, onSeek: { _ in })
        .padding()
}
