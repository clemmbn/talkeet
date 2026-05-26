/*
 * Segment.swift
 *
 * Purpose: Data model for a single time-bounded segment of a video.
 *
 * Responsibilities:
 *   - Represent a backend-returned segment with start/end times and type.
 *   - Provide Codable conformance matching the /analyze/silence JSON schema.
 *   - Provide Identifiable conformance for SwiftUI list rendering.
 *
 * Constraints:
 *   - `id` is derived from `start` (unique per segment in a contiguous list).
 *   - JSON keys use snake_case to match the Python backend response.
 */

import Foundation

// MARK: - SegmentType

/// The classification of a video segment returned by the silence-detection backend.
enum SegmentType: String, Codable, Equatable {
    case speech
    case silence
}

// MARK: - Segment

/// A time-bounded interval of a video, classified as speech or silence.
struct Segment: Codable, Identifiable, Equatable {
    /// Start time in seconds from the beginning of the video.
    let start: Double
    /// End time in seconds from the beginning of the video.
    let end: Double
    /// Whether this interval contains speech or silence.
    let type: SegmentType

    /// Unique identifier within a contiguous segment list (start time is unique per list).
    var id: Double { start }

    /// Duration of the segment in seconds.
    var duration: Double { end - start }
}
