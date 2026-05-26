/*
 * TalkeetTests.swift
 *
 * Purpose: Unit tests for Talkeet models, services, and view models.
 *
 * Responsibilities:
 *   - Verify Segment Codable round-trips.
 *   - Verify AnalysisService decodes backend responses and surfaces errors.
 *   - Verify ProjectViewModel state transitions.
 *
 * Constraints:
 *   - No real network or AVPlayer required — all external dependencies are mocked.
 */

import Testing
import Foundation
@testable import Talkeet

// MARK: - Segment Tests

@Suite("Segment")
struct SegmentTests {

    @Test func decodesFromJSON() throws {
        let json = """
        [
          {"start": 0.0, "end": 1.23, "type": "silence"},
          {"start": 1.23, "end": 4.56, "type": "speech"}
        ]
        """.data(using: .utf8)!

        let segments = try JSONDecoder().decode([Segment].self, from: json)

        #expect(segments.count == 2)
        #expect(segments[0].start == 0.0)
        #expect(segments[0].end == 1.23)
        #expect(segments[0].type == .silence)
        #expect(segments[1].type == .speech)
    }

    @Test func idIsUniquePerStart() {
        let a = Segment(start: 1.0, end: 2.0, type: .speech)
        let b = Segment(start: 3.0, end: 4.0, type: .silence)
        #expect(a.id != b.id)
    }

    @Test func durationIsEndMinusStart() {
        let seg = Segment(start: 1.5, end: 4.0, type: .speech)
        #expect(abs(seg.duration - 2.5) < 0.001)
    }
}
