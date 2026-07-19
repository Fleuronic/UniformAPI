// Copyright © Fleuronic LLC. All rights reserved.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Signals that dci.org is temporarily un-scrapeable — a Cloudflare 524
// "Connection timed out" origin error, or an IP block the solver couldn't clear.
// Callers bail the current sweep and retry next cycle rather than treat missing
// data as truth (which would wrongly delete real events).
enum ScraperError: Error {
	case notScrapeable(URL)
}

actor ScraperSession {
	private let session: URLSession

	// dci.org is behind a Cloudflare challenge, so its requests are always sent
	// through the headless-browser solver sidecar (residential proxy) named by
	// SOLVER_URL. Without a solver configured, requests go directly.
	private let solverURL = ProcessInfo.processInfo.environment["SOLVER_URL"]

	init() {
		let configuration = URLSessionConfiguration.default
		// dci.org (the only Cloudflare-challenged host) always goes through the
		// solver's real browser, so the direct session — which now only serves
		// dcxmuseum.org and the internal solver — just needs a plain User-Agent.
		configuration.httpAdditionalHeaders = [
			"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
		]
		session = URLSession(configuration: configuration)
	}

	func data(from url: URL) async throws -> (Data, URLResponse) {
		if solverURL != nil, isChallenged(url) {
			return (try await solvedData(from: url), Self.ok(for: url))
		}
		print("Fetching \(url.absoluteString)")
		return try await session.data(from: url)
	}

	func data(for request: URLRequest) async throws -> (Data, URLResponse) {
		if solverURL != nil, let url = request.url, isChallenged(url) {
			return (try await solvedData(from: url), Self.ok(for: url))
		}
		return try await session.data(for: request)
	}

	func string(from url: URL) async throws -> String {
		let (data, _) = try await data(from: url)
		return String(decoding: data, as: UTF8.self)
	}

	// Fetch a dci.org URL through the solver sidecar (residential proxy + real
	// browser), which clears the Cloudflare challenge. If dci.org isn't scrapeable
	// right now — the solver can't clear on any IP, the origin returns a
	// "Connection timed out" page, or the solver is unreachable — throw so the
	// caller bails the whole sweep and retries next cycle. A half-broken sweep
	// must never be trusted, since the recorded-events cleanup deletes events that
	// are absent from it.
	func solvedData(from url: URL) async throws -> Data {
		guard let solverURL, var components = URLComponents(string: solverURL) else {
			return try await session.data(from: url).0
		}

		components.path = "/fetch"
		components.queryItems = [.init(name: "url", value: url.absoluteString)]
		guard let solverRequestURL = components.url else {
			return try await session.data(from: url).0
		}

		var request = URLRequest(url: solverRequestURL)
		request.timeoutInterval = 300  // the solver may rotate through several IPs

		print("Solving challenge for \(url.absoluteString)")
		for attempt in 0..<10 {
			do {
				let (data, response) = try await session.data(for: request)
				guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
					// Solver couldn't clear on any IP: dci.org isn't scrapeable right
					// now, so bail the whole sweep instead of treating the event as gone.
					print("Could not clear \(url.absoluteString) on any IP — bailing")
					throw ScraperError.notScrapeable(url)
				}
				// dci.org's origin sometimes 524s behind Cloudflare: the challenge
				// clears but the body is a "Connection timed out" page. Same story —
				// bail rather than trust a half-broken sweep.
				if Self.isTimedOut(data) {
					print("dci.org timed out for \(url.absoluteString) — bailing")
					throw ScraperError.notScrapeable(url)
				}
				let rotations = http.value(forHTTPHeaderField: "X-Solver-Rotations") ?? "?"
				let seconds = (Double(http.value(forHTTPHeaderField: "X-Solver-Elapsed-Ms") ?? "") ?? 0) / 1000
				print("Solved in \(String(format: "%.1f", seconds))s (\(rotations) rotation(s))")
				return data
			} catch let error as URLError where Self.isSolverStarting(error) && attempt < 9 {
				// Solver sidecar not listening yet on a cold start: wait and retry.
				try? await Task.sleep(nanoseconds: 3_000_000_000)
			}
		}
		// Solver sidecar never became reachable — bail the sweep.
		print("Solver unreachable for \(url.absoluteString) — bailing")
		throw ScraperError.notScrapeable(url)
	}

	private func isChallenged(_ url: URL) -> Bool {
		url.host?.hasSuffix("dci.org") ?? false
	}

	private static func ok(for url: URL) -> URLResponse {
		HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
	}

	private static func isSolverStarting(_ error: URLError) -> Bool {
		[.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed].contains(error.code)
	}

	private static func isTimedOut(_ data: Data) -> Bool {
		!data.isEmpty && String(decoding: data, as: UTF8.self).contains("Connection timed out")
	}
}

let scraperSession = ScraperSession()
