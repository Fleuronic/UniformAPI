// Copyright © Fleuronic LLC. All rights reserved.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Shared scraper session that identifies itself via a descriptive User-Agent
// and throttles every request to at least one second apart, with a randomized
// jitter so the cadence is not perfectly periodic (a pattern WAFs can learn to
// flag). Implemented as an actor so concurrent callers are serialized and each
// request reserves a distinct, jittered slot, avoiding the request bursts that
// WAFs flag as suspicious activity.
actor ScraperSession {
	private let session: URLSession
	private var nextSlot: Date = .distantPast

	// Minimum spacing between requests and the upper bound once jitter is added.
	// Each slot is placed a random interval within this range after the last, so
	// requests are never faster than one per second but never perfectly regular.
	private let minInterval = 1.0
	private let maxInterval = 2.5

	init() {
		let configuration = URLSessionConfiguration.default
		configuration.httpAdditionalHeaders = [
			"User-Agent": "Corpsboard/1.0 (+https://github.com/Fleuronic/Corpsboard)"
		]
		session = URLSession(configuration: configuration)
	}

	func data(from url: URL) async throws -> (Data, URLResponse) {
		await waitForSlot()
		print("Fetching \(url.absoluteString)")
		return try await session.data(from: url)
	}

	func data(for request: URLRequest) async throws -> (Data, URLResponse) {
		await waitForSlot()
		return try await session.data(for: request)
	}

	// Fetches the contents of a URL as a UTF-8 string, carrying the session's
	// User-Agent header and the shared throttle.
	func string(from url: URL) async throws -> String {
		let (data, _) = try await data(from: url)
		return String(decoding: data, as: UTF8.self)
	}

	// Reserves the next available jittered slot and suspends until it arrives.
	// The reservation runs synchronously within the actor, so each concurrent
	// caller receives a distinct slot a random interval after the last.
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
