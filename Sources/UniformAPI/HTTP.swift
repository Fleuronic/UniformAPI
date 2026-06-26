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
		crashIfBlocked(result.1, for: url)
		return result
	}

	func data(for request: URLRequest) async throws -> (Data, URLResponse) {
		await waitForSlot()
		let result = try await session.data(for: request)
		crashIfBlocked(result.1, for: request.url)
		return result
	}

	func string(from url: URL) async throws -> String {
		let (data, _) = try await data(from: url)
		return String(decoding: data, as: UTF8.self)
	}

	private func crashIfBlocked(_ response: URLResponse, for url: URL?) {
		guard let response = response as? HTTPURLResponse, response.statusCode == 403 else { return }
		fatalError("dci.org returned 403 (blocked) for \(url?.absoluteString ?? "unknown URL")")
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
