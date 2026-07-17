// Copyright © Fleuronic LLC. All rights reserved.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor ScraperSession {
	private let session: URLSession
	private var nextSlot: Date = .distantPast

	private let minInterval = 1.0
	private let maxInterval = 2.5

	// When set (SOLVER_URL env), Cloudflare-challenged dci.org endpoints are
	// fetched through the headless-Chromium solver sidecar instead of directly.
	private let solverURL = ProcessInfo.processInfo.environment["SOLVER_URL"]

	init() {
		let configuration = URLSessionConfiguration.default
		configuration.httpAdditionalHeaders = [
			"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
			"Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
			"Accept-Language": "en-US,en;q=0.9",
			"Upgrade-Insecure-Requests": "1",
			"Sec-Fetch-Dest": "document",
			"Sec-Fetch-Mode": "navigate",
			"Sec-Fetch-Site": "none",
			"Sec-Fetch-User": "?1",
			"sec-ch-ua": "\"Not_A Brand\";v=\"8\", \"Chromium\";v=\"120\", \"Google Chrome\";v=\"120\"",
			"sec-ch-ua-mobile": "?0",
			"sec-ch-ua-platform": "\"macOS\""
		]
		session = URLSession(configuration: configuration)
	}

	func data(from url: URL) async throws -> (Data, URLResponse) {
		await waitForSlot()
		print("Fetching \(url.absoluteString)")
		let result = try await session.data(from: url)
		if isBlocked(result.1) {
			return (try await solvedData(from: url), result.1)
		}
		return result
	}

	func data(for request: URLRequest) async throws -> (Data, URLResponse) {
		await waitForSlot()
		let result = try await session.data(for: request)
		if isBlocked(result.1), let url = request.url {
			return (try await solvedData(from: url), result.1)
		}
		return result
	}

	func string(from url: URL) async throws -> String {
		let (data, _) = try await data(from: url)
		return String(decoding: data, as: UTF8.self)
	}

	// Fetch a Cloudflare-challenged URL via the solver sidecar (headless
	// Chromium), which solves the Managed Challenge and returns the raw body.
	// Falls back to a direct request when no solver is configured.
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
				guard (response as? HTTPURLResponse)?.statusCode == 200 else {
					throw URLError(.badServerResponse)
				}
				return data
			} catch let error as URLError where Self.isSolverStarting(error) && attempt < 9 {
				// The solver sidecar may not be listening yet on a cold start;
				// wait and retry so the first request doesn't fall back to a
				// direct fetch (which would then hit the challenge).
				try? await Task.sleep(nanoseconds: 3_000_000_000)
			}
		}
		throw URLError(.cannotConnectToHost)
	}

	private static func isSolverStarting(_ error: URLError) -> Bool {
		[.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed].contains(error.code)
	}

	private func isBlocked(_ response: URLResponse) -> Bool {
		// A 403 from dci.org means a Cloudflare challenge (or IP block); route that
		// request through the solver sidecar (residential proxy + real browser)
		// instead of failing.
		(response as? HTTPURLResponse)?.statusCode == 403
	}

	private func waitForSlot() async {
		let slot = max(Date(), nextSlot)
		nextSlot = slot.addingTimeInterval(.random(in: minInterval...maxInterval))
		let delay = slot.timeIntervalSinceNow
		if delay > 0 {
			try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
		}
	}
}

let scraperSession = ScraperSession()
