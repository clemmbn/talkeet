/*
 * ProjectViewModel.swift
 *
 * Purpose: Central state for a loaded video editing session.
 *
 * Responsibilities:
 *   - Own the AVPlayer for the currently loaded video.
 *   - Trigger POST /analyze/silence and POST /analyze/waveform on file load.
 *   - Expose isAnalyzing and errorMessage for UI feedback.
 *   - Provide seekToSegment(_:) so the segment list can drive playback.
 *   - Provide reset() so callers can cleanly tear down a session without
 *     leaving in-flight tasks running.
 *
 * Constraints:
 *   - @MainActor ensures AVPlayer and UI state mutations are always on the main thread.
 *   - analysisService is injected so tests can supply a mock without a real backend.
 *   - loadFile() cancels any in-flight tasks before starting new ones.
 *   - Silence analysis and waveform fetch run in parallel; either may fail independently.
 */

import AVKit
import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ProjectViewModel")

@Observable
@MainActor
final class ProjectViewModel {

    // MARK: - Public state (observed by SwiftUI views)

    /// URL of the currently loaded video file.
    var videoURL: URL?

    /// AVPlayer for the loaded video. Nil until loadFile() is called.
    var player: AVPlayer?

    /// Segments returned by the backend after silence analysis.
    var segments: [Segment] = []

    /// Normalized RMS amplitude buckets from POST /analyze/waveform. Empty until loaded.
    var waveformSamples: [Double] = []

    /// True while a /analyze/silence request is in flight.
    var isAnalyzing: Bool = false

    /// Non-nil when the last analysis attempt failed.
    var errorMessage: String?

    // MARK: - Private

    private let analysisService: AnalysisService
    /// Held so we can cancel an in-flight analysis when a new file is loaded.
    private var analysisTask: Task<Void, Never>?
    /// Held so we can cancel an in-flight waveform fetch when a new file is loaded.
    private var waveformTask: Task<Void, Never>?

    /// - Parameter analysisService: Injected for testability (default uses URLSession.shared).
    init(analysisService: AnalysisService = AnalysisService()) {
        self.analysisService = analysisService
    }

    // MARK: - File loading

    /// Loads a video file into the player and triggers silence analysis + waveform fetch in parallel.
    /// Cancels any in-flight tasks before starting new ones.
    /// - Parameter url: Absolute URL of the video file on disk.
    func loadFile(_ url: URL) {
        // Cancel any previous tasks so we don't update state from stale requests.
        analysisTask?.cancel()
        waveformTask?.cancel()

        videoURL = url
        player = AVPlayer(url: url)
        segments = []
        waveformSamples = []
        errorMessage = nil
        isAnalyzing = true

        log.info("Loading file: \(url.lastPathComponent, privacy: .public)")

        analysisTask = Task { [weak self] in
            await self?.runAnalysis(for: url)
        }

        // Waveform fetch runs in parallel — a failure here is non-fatal (view stays empty).
        waveformTask = Task { [weak self] in
            await self?.runWaveformFetch(for: url)
        }
    }

    // MARK: - Session teardown

    /// Cancels any in-flight tasks and resets all session state.
    /// Call this when the user closes a file to return to the drop zone.
    func reset() {
        // Cancel before zeroing isAnalyzing so the deferred flag-clear in runAnalysis
        // doesn't race with the explicit reset below.
        analysisTask?.cancel()
        analysisTask = nil
        waveformTask?.cancel()
        waveformTask = nil
        videoURL = nil
        player = nil
        segments = []
        waveformSamples = []
        errorMessage = nil
        isAnalyzing = false
        log.info("Session reset")
    }

    // MARK: - Playback

    /// Seeks the player to the start of the given segment.
    /// - Parameter segment: The segment whose start time to seek to.
    func seekToSegment(_ segment: Segment) {
        // Use toleranceBefore/After .zero for frame-accurate seeking.
        let time = CMTime(seconds: segment.start, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        log.debug("Seeking to segment start: \(segment.start, privacy: .public)s")
    }

    // MARK: - Private

    /// Calls the analysis service and updates state on the main actor.
    private func runAnalysis(for url: URL) async {
        defer {
            // Only clear the flag if this task was not superseded by reset() or a new
            // loadFile() — those callers have already set isAnalyzing to its correct value.
            if !Task.isCancelled {
                isAnalyzing = false
            }
        }

        do {
            let result = try await analysisService.analyzeSilence(filePath: url.path)
            // Check for cancellation before mutating shared state.
            guard !Task.isCancelled else { return }
            segments = result
            log.info("Analysis complete: \(result.count, privacy: .public) segments")
        } catch is CancellationError {
            log.debug("Analysis cancelled for \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("Analysis failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches waveform amplitude data from the backend; failure is non-fatal (waveform stays empty).
    private func runWaveformFetch(for url: URL) async {
        do {
            let samples = try await analysisService.fetchWaveform(filePath: url.path)
            guard !Task.isCancelled else { return }
            waveformSamples = samples
            log.info("Waveform loaded: \(samples.count, privacy: .public) samples")
        } catch is CancellationError {
            log.debug("Waveform fetch cancelled for \(url.lastPathComponent, privacy: .public)")
        } catch {
            // Non-fatal: log and leave waveformSamples empty so the view shows nothing.
            log.warning("Waveform fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
