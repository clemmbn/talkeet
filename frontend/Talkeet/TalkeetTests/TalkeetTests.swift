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

// MARK: - AnalysisService Tests

/// A mock HTTP client that returns a fixed response for any request.
struct MockHTTPClient: HTTPClient {
    /// The data to return on every call.
    let responseData: Data
    /// The HTTP status code to simulate.
    let statusCode: Int

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

@Suite("AnalysisService")
struct AnalysisServiceTests {

    @Test func returnsSegmentsOnSuccess() async throws {
        let json = """
        [
          {"start": 0.0, "end": 1.0, "type": "silence"},
          {"start": 1.0, "end": 5.0, "type": "speech"}
        ]
        """.data(using: .utf8)!
        let client = MockHTTPClient(responseData: json, statusCode: 200)
        let service = AnalysisService(client: client)

        let segments = try await service.analyzeSilence(filePath: "/fake/video.mp4")

        #expect(segments.count == 2)
        #expect(segments[0].type == .silence)
        #expect(segments[1].type == .speech)
    }

    @Test func throwsOnNon200Response() async throws {
        let client = MockHTTPClient(responseData: Data(), statusCode: 404)
        let service = AnalysisService(client: client)

        do {
            _ = try await service.analyzeSilence(filePath: "/fake/video.mp4")
            Issue.record("Expected throw but got result")
        } catch AnalysisError.httpError(let code) {
            #expect(code == 404)
        }
    }

    @Test func sendsCorrectJSONBody() async throws {
        // Capture the outgoing request body to assert the file_path key.
        actor RequestCapture: HTTPClient {
            var capturedBody: Data?
            let responseData: Data

            init(responseData: Data) {
                self.responseData = responseData
            }

            func data(for request: URLRequest) async throws -> (Data, URLResponse) {
                capturedBody = request.httpBody
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil)!
                return (responseData, response)
            }
        }

        let json = "[]".data(using: .utf8)!
        let capture = RequestCapture(responseData: json)
        let service = AnalysisService(client: capture)
        _ = try await service.analyzeSilence(filePath: "/my/video.mp4")

        let body = await capture.capturedBody
        let decoded = try JSONDecoder().decode([String: String].self, from: body!)
        #expect(decoded["file_path"] == "/my/video.mp4")
    }
}
