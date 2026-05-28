/*
 * WaveformView.swift
 *
 * Purpose: Renders a scrollable, zoomable audio waveform with color-coded segment
 *          regions, a real-time playhead, and tap/drag-to-seek interaction.
 *
 * Responsibilities:
 *   - Draw normalized RMS amplitude buckets as vertical bars in a SwiftUI Canvas.
 *   - Color-code background regions by segment type:
 *       speech  → clear (neutral, no tint)
 *       silence → red tint (highlighted for removal)
 *   - Draw a playhead line at the currentTime position (updated at ~30 fps).
 *   - Support horizontal scrolling (two-finger swipe on the trackpad) via ScrollView.
 *   - Support pinch-to-zoom via MagnifyGesture; zoom range [1×, 50×].
 *     At 1× the canvas exactly fills the viewport width; zooming expands the canvas
 *     so more resolution becomes visible inside the scroll container.
 *   - Show a compact zoom-level badge (top-right) when zoomed in; tap it to reset.
 *   - Translate tap/drag x-position to a time value and call onSeek so the
 *     AVPlayer follows user scrubbing. The drag location is in canvas (content)
 *     space, so seek accuracy is maintained at any zoom level.
 *   - Show a placeholder when samples have not yet loaded.
 *
 * Constraints:
 *   - `duration` is derived from segments.last?.end so no extra state is needed.
 *   - Canvas redraws automatically when samples, segments, or currentTime change.
 *   - Bar width is clamped to ≥ 1 pt so bars remain visible at any zoom level.
 *   - MagnifyGesture uses simultaneousGesture so the ScrollView's scroll handling
 *     (two-finger swipe) is not blocked.
 *   - Zoom state (@State) is internal to the view; the ViewModel does not need it.
 *   - Auto-scroll fires on every currentTime tick (~30 fps) only when zoomed in;
 *     suppressed during user scrub (isDragging = true) to avoid fighting the user.
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
    /// Zoom level committed at gesture end; read at the start of each subsequent gesture
    /// so delta magnification from `MagnifyGesture.Value.magnification` accumulates correctly.
    @State private var gestureBaseZoom: CGFloat = 1.0
    /// True while the user is dragging to seek; suppresses auto-scroll during scrub.
    @State private var isDragging: Bool = false

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

    /// Builds the scrollable, zoomable waveform canvas.
    /// Layout: GeometryReader → ZStack → ScrollViewReader → ScrollView(.horizontal) → ZStack → Canvas.
    /// The Canvas width = geo.size.width × zoomScale; at 1× it fills the viewport exactly.
    /// During playback at zoom > 1×, auto-scrolls to keep the playhead centered via ScrollViewReader.
    /// The zoom-reset badge sits in the outer ZStack so it stays fixed in the viewport.
    private var waveformCanvas: some View {
        // GeometryReader captures the viewport width so contentWidth can be derived.
        GeometryReader { geo in
            let duration     = segments.last?.end ?? 0
            // At zoomScale 1.0 the canvas exactly fills the viewport; >1.0 it overflows into scroll.
            let contentWidth = geo.size.width * zoomScale

            ZStack(alignment: .topTrailing) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            Canvas { context, size in
                                drawSegmentBackgrounds(context: context, size: size, duration: duration)
                                drawWaveformBars(context: context, size: size)
                                drawPlayhead(context: context, size: size, duration: duration)
                            }

                            // Invisible 1 pt anchor positioned at the playhead X.
                            // ScrollViewReader uses this to scroll the timeline during playback.
                            // Padding changes with currentTime; offset is layout-affecting so
                            // scrollTo finds the correct position each tick.
                            Color.clear
                                .frame(width: 1, height: 1)
                                .padding(.leading, duration > 0
                                    ? CGFloat(min(currentTime, duration) / duration) * contentWidth
                                    : 0)
                                .id("waveform-playhead-anchor")
                        }
                        .frame(width: contentWidth, height: geo.size.height)
                        // DragGesture location is in canvas (content) space, so seek is accurate
                        // at any zoom level without knowing the current scroll offset.
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    guard duration > 0, contentWidth > 0 else { return }
                                    let fraction = Double(value.location.x / contentWidth)
                                    onSeek(max(0, min(fraction * duration, duration)))
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )
                    }
                    // Auto-scroll: when zoomed in and the video is playing (not scrubbing),
                    // keep the playhead centered in the viewport.
                    // Note: if the user is two-finger-scrolling simultaneously, the scroll
                    // may conflict; this is an acceptable tradeoff for the first implementation.
                    .onChange(of: currentTime) { _, _ in
                        guard zoomScale > 1.01, !isDragging else { return }
                        proxy.scrollTo("waveform-playhead-anchor", anchor: .center)
                    }
                }

                // Zoom indicator badge — visible only when zoomed in; tap to reset.
                // 1.01 threshold provides hysteresis: avoids the badge flickering on/off due
                // to floating-point imprecision when zoom is clamped back toward 1.0.
                if zoomScale > 1.01 {
                    zoomResetButton
                }
            }
            // simultaneousGesture lets the ScrollView handle two-finger swipe while also
            // recognising trackpad pinch via MagnifyGesture.
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let newScale = gestureBaseZoom * value.magnification
                        zoomScale = max(1.0, min(50.0, newScale))
                    }
                    .onEnded { value in
                        let finalScale = gestureBaseZoom * value.magnification
                        zoomScale = max(1.0, min(50.0, finalScale))
                        // Persist the final scale so the next gesture accumulates from here.
                        gestureBaseZoom = zoomScale
                    }
            )
        }
    }

    // MARK: - Zoom reset overlay

    /// Small badge in the top-right corner showing the current zoom level.
    /// Tapping it resets zoom to fit-to-width (1.0×) with a brief animation.
    private var zoomResetButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                zoomScale = 1.0
                gestureBaseZoom = 1.0
            }
        } label: {
            Text(String(format: "%.0f×", zoomScale))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .padding(4)
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
    /// Reads `self.samples`; no-ops when samples is empty.
    /// - Parameters:
    ///   - context: The active Canvas graphics context.
    ///   - size: Full canvas size in points.
    private func drawWaveformBars(context: GraphicsContext, size: CGSize) {
        // Guard: body shows placeholder when samples are empty; this helper is never called then,
        // but guard defensively to make the empty-array no-op explicit.
        guard !samples.isEmpty else { return }
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
        // Clamp to [0, duration] in case currentTime races ahead of a segment update on file re-open.
        let x = CGFloat(min(currentTime, duration) / duration) * size.width
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
