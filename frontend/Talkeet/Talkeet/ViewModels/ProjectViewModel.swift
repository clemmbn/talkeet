/*
 * ProjectViewModel.swift
 *
 * Purpose: Central state for a loaded video editing session.
 *
 * Responsibilities:
 *   - Own the AVPlayer for the currently loaded video.
 *   - Trigger POST /analyze/silence and POST /analyze/waveform on file load.
 *   - Expose isAnalyzing and errorMessage for UI feedback.
 *   - Provide seekToSegment(_:) and seekToTime(_:) so the segment list and
 *     waveform timeline can drive playback.
 *   - Track currentTime via a periodic AVPlayer observer for playhead sync.
 *   - Provide reset() so callers can cleanly tear down a session without
 *     leaving in-flight tasks running.
 *
 * Constraints:
 *   - @MainActor ensures AVPlayer and UI state mutations are always on the main thread.
 *   - analysisService is injected so tests can supply a mock without a real backend.
 *   - loadFile() cancels any in-flight tasks before starting new ones.
 *   - Silence analysis and waveform fetch run in parallel; either may fail independently.
 *   - The time observer is removed from the old player before a new one is created,
 *     preventing dangling observer references.
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

    /// Current playback position in seconds; updated at ~30 fps via a periodic AVPlayer observer.
    var currentTime: Double = 0

    // MARK: - Private

    private let analysisService: AnalysisService
    /// Held so we can cancel an in-flight analysis when a new file is loaded.
    private var analysisTask: Task<Void, Never>?
    /// Held so we can cancel an in-flight waveform fetch when a new file is loaded.
    private var waveformTask: Task<Void, Never>?
    /// Token returned by addPeriodicTimeObserver; must be removed before the player is replaced.
    private var timeObserver: Any?

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

        // Remove the observer from the OLD player before replacing it; the observer
        // token is tied to the specific AVPlayer instance it was registered on.
        removeTimeObserver()

        videoURL = url
        player = AVPlayer(url: url)
        setupTimeObserver()
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
        // Remove observer before niling the player — the token is invalid once the
        // player is deallocated.
        removeTimeObserver()
        videoURL = nil
        player = nil
        segments = []
        waveformSamples = []
        errorMessage = nil
        isAnalyzing = false
        currentTime = 0
        log.info("Session reset")
    }

    // MARK: - Playback

    /// Seeks the player to the start of the given segment.
    /// - Parameter segment: The segment whose start time to seek to.
    func seekToSegment(_ segment: Segment) {
        seekToTime(segment.start)
    }

    /// Seeks the player to a specific time in seconds and immediately updates currentTime
    /// so the playhead snaps to the tapped position without waiting for the next observer tick.
    /// - Parameter time: Target time in seconds.
    func seekToTime(_ time: Double) {
        // Use toleranceBefore/After .zero for frame-accurate seeking.
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        // Mirror the seek position immediately so the playhead doesn't lag behind.
        currentTime = time
        log.debug("Seeking to: \(time, privacy: .public)s")
    }

    // MARK: - Private

    /// Registers a 30 fps periodic observer on the current player to update currentTime.
    /// Must be called after self.player is set to a new instance.
    private func setupTimeObserver() {
        guard let player else { return }
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // We specified queue: .main so we are on the main thread, but the compiler
            // doesn't know that — use assumeIsolated to satisfy Swift 6 strict concurrency.
            MainActor.assumeIsolated {
                self?.currentTime = time.seconds
            }
        }
    }

    /// Removes the periodic time observer from the current player and clears the token.
    private func removeTimeObserver() {
        guard let observer = timeObserver else { return }
        player?.removeTimeObserver(observer)
        timeObserver = nil
    }

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
