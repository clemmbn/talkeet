/*
 * AnalysisService.swift
 *
 * Purpose: Wraps the POST /analyze/silence backend endpoint.
 *
 * Responsibilities:
 *   - Encode the request body (file_path + default silence parameters).
 *   - Decode the response JSON into [Segment].
 *   - Surface HTTP errors as AnalysisError.httpError(statusCode).
 *
 * Constraints:
 *   - Uses the HTTPClient protocol so the network layer is mockable in tests.
 *   - Default parameters match the backend defaults; callers may override in M9.
 */

import Foundation

// MARK: - AnalysisError

/// Errors surfaced by AnalysisService.
enum AnalysisError: Error, Equatable {
    /// The backend returned a non-200 HTTP status.
    case httpError(Int)
}

// MARK: - Private request model

/// Request body for POST /analyze/silence.
private struct SilenceRequest: Encodable {
    let filePath: String

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
    }
}

// MARK: - AnalysisService

/// Calls the silence-detection endpoint and returns decoded segments.
final class AnalysisService: Sendable {
    private let client: HTTPClient
    private let baseURL: URL

    /// - Parameters:
    ///   - client: HTTP client to use (default: URLSession.shared).
    ///   - baseURL: Backend base URL (default: http://127.0.0.1:8742).
    init(
        client: HTTPClient = URLSession.shared,
        baseURL: URL = URL(string: "http://127.0.0.1:8742")!
    ) {
        self.client = client
        self.baseURL = baseURL
    }

    /// Posts a video file path to /analyze/silence and returns the segment list.
    /// - Parameter filePath: Absolute path to the video file on disk.
    /// - Returns: Array of segments covering the full video duration.
    /// - Throws: `AnalysisError.httpError` on non-200; decoding errors on malformed JSON.
    func analyzeSilence(filePath: String) async throws -> [Segment] {
        let url = baseURL.appending(path: "analyze/silence")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SilenceRequest(filePath: filePath))

        let (data, response) = try await client.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AnalysisError.httpError(code)
        }

        return try JSONDecoder().decode([Segment].self, from: data)
    }
}
