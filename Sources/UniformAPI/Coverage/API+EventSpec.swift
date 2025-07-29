// Copyright © Fleuronic LLC. All rights reserved.

import Kanna
import Foundation
import struct Uniform.Event
import protocol Catena.ResultProviding
import protocol UniformService.EventSpec

extension API: EventSpec {
	public func listEvents() async -> Results<EventSpecifiedFields> {
		let year = 2025
		let formatStyle = Date.FormatStyle().month(.wide).day().year()

		do {
			let events = try (6...6).compactMap { index -> EventSpecifiedFields? in
				let showID = String(format: "%03d", index)
				let url = URL(string: "https://www.dcxmuseum.org/show.cfm?view=show&ShowID=\(year)\(showID)")!
				let html = try String(contentsOf: url, encoding: .utf8)

				guard 
					let doc = try? HTML(html: html, encoding: .utf8),
					let header = (doc.xpath("//th[1]")
						.first?
						.innerHTML!
						.components(separatedBy: "<br>")
						.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) else { return nil }

				let location = header[2]
				let components = location.split(separator: " ")
				let stateIndex = components.firstIndex { $0.count == 2 }!
				let city = components[0..<stateIndex].joined(separator: " ")
				let state = String(components[stateIndex])
				let country = components[(stateIndex + 1)...].joined(separator: " ")

				return try EventSpecifiedFields(
					id: .init(rawValue: Int(showID)!),
					date: Date(header[1], strategy: formatStyle.parseStrategy),
					city: city,
					state: state,
					country: country,
					show: header[0],
					circuit: header[3]
				)
			}
	
			return .success(events)
		} catch {
			return .failure(error)
		}
	}
}
