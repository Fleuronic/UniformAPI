// Copyright © Fleuronic LLC. All rights reserved.

import Kanna
import Foundation
import Uniform
import struct DrumKit.Event
import struct DrumKit.Location
import struct DrumKit.Circuit
import struct DrumKit.Show
import struct DrumKitService.IdentifiedEvent
import protocol Catena.ResultProviding
import protocol UniformService.EventSpec

extension API: EventSpec {
	public func listEvents(for year: Int) async -> Results<EventSpecifiedFields> {
		let formatStyle = Date.FormatStyle().month(.wide).day().year()

		do {
			let events = try (1...99).compactMap { index -> EventSpecifiedFields? in
				guard
					case let showID = String(format: "%03d", index),
					let url = URL(string: "https://www.dcxmuseum.org/show.cfm?view=show&ShowID=\(year)\(showID)"),
					case let html = try String(contentsOf: url, encoding: .utf8),
					let doc = try? HTML(html: html, encoding: .utf8),
					let header = (doc.xpath("//th[1]")
						.first?
						.innerHTML!
						.components(separatedBy: "<br>")
						.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) else { return nil }

				let id = Uniform.Event.ID(rawValue: Int(showID)!)
				let date = try! Date(header[1], strategy: formatStyle.parseStrategy)
				let show = header[0]
				let location = header[2].replacingOccurrences(of: ",", with: "")
				let circuit = header[3]

				return  .init(
					id: id,
					date: date,
					location: EventSpecifiedFields.EventLocationFields(name: location),
					circuit: EventSpecifiedFields.EventCircuitFields(name: circuit),
					show: EventSpecifiedFields.EventShowFields(name: show)
				)
			}

			return .success(events)
		} catch {
			return .failure(.network(error as NSError))
		}
	}

	public func createEvent(on date: Date, inLocationWith locationID: Location.ID, byCircuitWith circuitID: Circuit.ID?, forShowWith showID: Show.ID?) async -> SingleResult<DrumKit.Event.ID> {
		await insert(
			EventInput(
				date: date, 
				locationID: locationID, 
				circuitID: circuitID, 
				showID: showID
			)
		)	
	}
}
