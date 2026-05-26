/*
 * HTTPClient.swift
 *
 * Purpose: Protocol abstracting URLSession's data(for:) for dependency injection.
 *
 * Responsibilities:
 *   - Allow services to be tested without real network calls.
 *
 * Constraints:
 *   - Must be Sendable so actor-isolated code can hold a reference.
 *   - URLSession already satisfies this protocol without modification.
 */

import Foundation

/// Abstracts a single HTTP request-response exchange.
/// URLSession conforms automatically; tests supply a mock.
protocol HTTPClient: Sendable {
    /// Performs an HTTP request and returns the response body and metadata.
    /// - Parameter request: The URLRequest to execute.
    /// - Returns: A tuple of (body data, URL response).
    /// - Throws: Any URLSession-level error (network unavailable, timeout, etc.).
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}
