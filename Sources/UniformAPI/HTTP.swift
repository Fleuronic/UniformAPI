// Copyright © Fleuronic LLC. All rights reserved.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Shared URLSession that identifies the scraper to servers via a descriptive
// User-Agent. A custom session is required because the User-Agent of
// `URLSession.shared` cannot be overridden.
let scraperSession: URLSession = {
	let configuration = URLSessionConfiguration.default
	configuration.httpAdditionalHeaders = [
		"User-Agent": "Corpsboard/1.0 (+https://github.com/Fleuronic/Corpsboard)"
	]
	return URLSession(configuration: configuration)
}()

extension URLSession {
	// Fetches the contents of a URL as a UTF-8 string, replacing
	// `String(contentsOf:)` so requests carry the session's User-Agent header.
	func string(from url: URL) async throws -> String {
		let (data, _) = try await data(from: url)
		return String(decoding: data, as: UTF8.self)
	}
}
