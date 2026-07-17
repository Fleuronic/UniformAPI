// Copyright © Fleuronic LLC. All rights reserved.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor ScraperSession {
	private let session: URLSession

	// dci.org is behind a Cloudflare challenge, so its requests are always sent
	// through the headless-browser solver sidecar (residential proxy) named by
	// SOLVER_URL. Without a solver configured, requests go directly.
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
			"sec-ch-ua": "\"Not_A Brand\";v=\"8\", \"Chromium\";v=\"120\", \"Google Chrome\";v=\"120\"",
			"sec-ch-ua-mobile": "?0",
			"sec-ch-ua-platform": "\"macOS\""
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
	// browser), which clears the Cloudflare challenge. If the solver cannot
	// clear it on any residential IP, that is an IP-level block that should
	// never happen — crash so we stop and notice, rather than degrade silently.
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
					fatalError("dci.org blocked the solver's residential IP for \(url.absoluteString)")
				}
				return data
			} catch let error as URLError where Self.isSolverStarting(error) && attempt < 9 {
				// Solver sidecar not listening yet on a cold start: wait and retry.
				try? await Task.sleep(nanoseconds: 3_000_000_000)
			}
		}
		fatalError("solver sidecar unreachable for \(url.absoluteString)")
	}

	private func isChallenged(_ url: URL) -> Bool {
		url.host?.hasSuffix("dci.org") ?? false
	}

	private static func ok(for url: URL) -> URLResponse {
		HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) ?? URLResponse()
	}

	private static func isSolverStarting(_ error: URLError) -> Bool {
		[.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed].contains(error.code)
	}
}

let scraperSession = ScraperSession()
