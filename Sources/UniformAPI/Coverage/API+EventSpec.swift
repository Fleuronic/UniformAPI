// Copyright © Fleuronic LLC. All rights reserved.

import Kanna
import Foundation
import Uniform
import struct DrumKit.Event
import struct DrumKit.Location
import struct DrumKit.Circuit
import struct DrumKit.Show
import struct DrumKit.Venue
import struct DrumKitService.IdentifiedEvent
import protocol Catena.ResultProviding
import protocol UniformService.EventSpec

extension API: EventSpec {
	public func listEvents(for year: Int) async -> Results<EventSpecifiedFields> {
		let formatStyle = Date.FormatStyle().month(.wide).day().year()

		do {
			let events = try (54...54).compactMap { index -> EventSpecifiedFields? in
				guard
					case let showID = String(format: "%03d", index),
					let url = URL(string: "https://www.dcxmuseum.org/show.cfm?view=show&ShowID=\(year)\(showID)"),
					case let html = try String(contentsOf: url, encoding: .utf8),
					let doc = try? HTML(html: html, encoding: .utf8),
					let header = (doc.xpath("//th[1]")
						.first?
						.innerHTML?
						.components(separatedBy: "<br>")
						.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) else { return nil }

				var idRows = doc.xpath("//td")
					.compactMap { element in
						if let url = element.xpath("a").first?["href"] {
							let components = url.components(separatedBy: "=")
							if  components.count > 2 {
								return components[2].components(separatedBy: "&")[0]
							} else {
								return element.text
							}
						} else {
							return element.text
						}
					}
					.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

				let id = Uniform.Event.ID(rawValue: Int(showID)!)
				let date = try! Date(header[1], strategy: formatStyle.parseStrategy)
				let show = EventSpecifiedFields.EventShowFields(name: header[0])
				let location = EventSpecifiedFields.EventLocationFields(name: header[2])
				let circuit = EventSpecifiedFields.EventCircuitFields(name: header[3])
				let slug = (show?.name).flatMap(Show.slug)
				let detailsURL = slug.flatMap { URL(string: "https://www.dci.org/events/\(year)-\($0)/") }
				let scoresURL = slug.flatMap { URL(string: "https://www.dci.org/scores/final-scores/\(year)-\($0)/") }

				guard 
					let detailsURL,
					let html = try? String(contentsOf: detailsURL, encoding: .utf8),
					let doc = try? HTML(html: html, encoding: .utf8),
					let slotRows = (doc.xpath("//tbody[1]")
						.first?
						.xpath("//td")
						.compactMap(\.text)),
					let addressComponents = (doc.xpath("//address")
						.first?
						.innerHTML?
						.components(separatedBy: "<br>")
						.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
						.filter { !$0.isEmpty }) else { return nil }
				
				let venueName = addressComponents.count == 3 ? addressComponents[0] : nil
				let venue = venueName.map { name in
					EventSpecifiedFields.EventVenueFields(
						name: name,
						address: EventSpecifiedFields.EventVenueFields.VenueAddressFields(
							records: addressComponents.suffix(2)
						)
					)
				}

				let scoreRows: [String]? = if 
					let scoresURL,
					let html = try? String(contentsOf: scoresURL, encoding: .utf8),
					let doc = try? HTML(html: html, encoding: .utf8) {
					doc
						.xpath("//div[@class='score-tbl responsive-tbl finalscores']")
						.first?
						.xpath("/div")
						.compactMap(\.text)
						.map { $0.replacingOccurrences(of: "[\\r\\n ]+", with: " ", options: .regularExpression) }
						.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
						.filter { $0 != "Place Corps Score" && !$0.contains("Powered") }
				} else { nil }

				let slots = slotRows
					.chunked(into: 2)
					.map { ($0[0], $0[1]) }
					.map(EventSpecifiedFields.EventSlotFields.init)

				// print(show!.name)
				// print(idRows)
				// print(slotRows)

				// return nil
				return .init(
					id: id,
					date: date,
					location: location,
					circuit: circuit,
					show: show,
					venue: venue,
					slots: slots
				)
			}

			return .success(events)
		} catch {
			return .failure(.network(error as NSError))
		}
	}

	public func createEvent(on date: Date, inLocationWith locationID: Location.ID, byCircuitWith circuitID: Circuit.ID?, forShowWith showID: Show.ID?, atVenueWith venueID: Venue.ID?) async -> SingleResult<DrumKit.Event.ID> {
		await insert(
			EventInput(
				date: date, 
				locationID: locationID, 
				circuitID: circuitID, 
				showID: showID,
				venueID: venueID
			)
		)	
	}
}

private extension API {
	
}

// MARK: -
private extension Array {
	func chunked(into size: Int) -> [[Element]] {
		return stride(from: 0, to: count, by: size).map {
			Array(self[$0 ..< Swift.min($0 + size, count)])
		}
	}
}
