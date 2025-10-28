// Copyright © Fleuronic LLC. All rights reserved.

import Kanna
import Foundation
import Uniform
import struct DrumKit.Event
import struct DrumKit.Location
import struct DrumKit.Circuit
import struct DrumKit.Show
import struct DrumKit.Venue
import struct DrumKit.Placement
import struct DrumKitService.IdentifiedEvent
import protocol Catena.ResultProviding
import protocol UniformService.EventSpec

extension API: EventSpec {
	public func listEvents(for year: Int, with corpsRecord: (String) async -> String) async -> Results<EventSpecifiedFields> {
		var slugs: [String: Int] = [:]
		let formatStyle = Date.FormatStyle().month(.wide).day().year()

		do {
			var events: [EventSpecifiedFields] = []
			for index in 1...147 {
				guard
					case let showID = String(format: "%03d", index),
					let url = URL(string: "https://www.dcxmuseum.org/show.cfm?view=show&ShowID=\(year)\(showID)"),
					case let html = try String(contentsOf: url, encoding: .utf8),
					let doc = try? HTML(html: html, encoding: .utf8),
					let header = (doc.xpath("//th[1]")
						.first?
						.innerHTML?
						.components(separatedBy: "<br>")
						.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
					!header[2].isEmpty, !header[2].contains("Online") else { continue }

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
				let location = EventSpecifiedFields.EventLocationFields(name: header[2])
				let show = EventSpecifiedFields.EventShowFields(name: header[0], city: location?.city, year: year)
				let slug = (show?.name).flatMap { Show.slug(forShowNamed: $0, in: year) }
				
				guard 
					/* Year from date matches year */
					Show.isValid(with: show?.name) else { continue }

				let detailsURL: URL?
				let scoresURL: URL?
				if let slug {
					slugs[slug, default: 0] += 1
					let count = slugs[slug]!
					let eventSlug = count > 1 ? "\(slug)-\(count)" : slug
					let scoreSlug = Show.scoreSlug(for: eventSlug, in: location?.city, year: year)

					detailsURL = year >= 2019 ? .init(string: "https://www.dci.org/events/\(year)-\(eventSlug)/") : nil
					scoresURL = year >= 2013 ? .init(string: "https://www.dci.org/scores/final-scores/\(year)-\(scoreSlug)/") : nil
				} else {
					detailsURL = nil
					scoresURL = nil
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

				var divisionName: String? = nil
				var exhibitionCorps: [String] = []
				var placements: [String: EventSpecifiedFields.EventSlotFields.SlotPlacementFields] = [:]
				let circuit = EventSpecifiedFields.EventCircuitFields(name: scoreRows == nil ? header[3] : "DCI")

				if let scoreRows {
					for row in scoreRows {
						let components = row.components(separatedBy: " ")
						let rank = Int(components[0])
						if let rank {
							let corps = components.dropFirst().dropLast().joined(separator: " ")
							let score = Double(components.last!)!

							if score > 0 {
								placements[corps] = .init(
									rank: rank,
									score: score,
									divisionName: divisionName!,
									circuitAbbreviation: circuit.abbreviation
								)
							} else {
								exhibitionCorps.append(corps)
							}
						} else {
							divisionName = row.replacingOccurrences(of: " - ", with: " ")
						}
					}
				}

				var slotRows: [String] = []
				let addressComponents: [String]
				let timeZone: String

				if 
					let detailsURL,
					let html = try? String(contentsOf: detailsURL, encoding: .utf8),
					let doc = try? HTML(html: html, encoding: .utf8),
					let tableHeader = doc.xpath("//div[@class='lineup-times-table']/div/p").first?.text {
					slotRows = (doc.xpath("//div[@class='table-responsive common-table']/table/tbody[1]")
						.first!
						.xpath("//td")
						.compactMap(\.text))
					addressComponents = (doc.xpath("//address")
						.first!
						.innerHTML!
						.components(separatedBy: "<br>")
						.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
						.filter { !$0.isEmpty })
					timeZone = tableHeader.components(separatedBy: " ")[2]
				} else {
					let corps = placements.keys + exhibitionCorps
					let hasPictures = 
						idRows.count > 10 && idRows[10] == "0" || 
						idRows.count > 60 && idRows[60] == "0" || 
						idRows.count > 180 && idRows[180] == "0" ||
						idRows[0] == "0"
					// print(idRows)
					let (initial, multiple) = hasPictures ? (3, 5) : (2, 4)
					let ids = stride(from: initial, through: idRows.count - 1, by: multiple).map { idRows[$0] }

					var records: [String] = []

					for id in ids where !id.contains("-") && id != "99999" {
						let record = await corpsRecord(id)
						let name = record.components(separatedBy: " - ")[0]

						if !corps.contains(name) {
							records.append(record)
							let index = idRows
								.enumerated()
								.first { $0.element == id && $0.offset % multiple == initial }!
								.offset
							
							let divisionName = idRows[index - 2]
							let defaultDivisionName = "World Class"
								
							if let rank = Int(idRows[index - 1]), let score = Double(idRows[index + 1]) {
								placements[name] = .init(
									rank: rank,
									score: score,
									divisionName: divisionName.isEmpty ? defaultDivisionName : divisionName,
									circuitAbbreviation: circuit.abbreviation
								)
							}
						}
					}

					for record in records {
						if record.contains(" ,") || record.hasSuffix(" ") { fatalError() }
						slotRows += ["", record]
					}

					for corps in corps {
						let record = await corpsRecord(corps)
						if record.contains(" ,") || record.hasSuffix(" ") { fatalError() }
						slotRows += ["", record]
					}

					addressComponents = []
					timeZone = "GMT"
				}

				let venueName = addressComponents.count == 3 ? addressComponents[0] : nil
				let venue = venueName.map { name in
					EventSpecifiedFields.EventVenueFields(
						name: venueName ?? "",
						address: EventSpecifiedFields.EventVenueFields.VenueAddressFields(
							records: addressComponents.suffix(2)
						)
					)	
				}

				let hasTimes = timeZone != "GMT"
				let slots = slotRows.chunked(into: 2).map { row in
					let time = row[0]
					let name = row[1]
					let record = name.components(separatedBy: " - ")[0]
					let groupName = Placement.groupName(for: record)

					return EventSpecifiedFields.EventSlotFields(
						time: time,
						name: name,
						placement: placements[groupName],
						isPotentiallyEncore: hasTimes
					)
				}

				let event = EventSpecifiedFields(
					id: id,
					date: date,
					detailsURL: detailsURL,
					scoresURL: scoresURL,
					timeZone: timeZone,
					location: location,
					circuit: circuit,
					show: show,
					venue: venue,
					slots: slots
				)

				// print(event)
				if let event {
					events.append(event)
				}
			}

			return .success(events)
		} catch {
			return .failure(.network(error as NSError))
		}
	}

	public func createEvent(on date: Date, inLocationWith locationID: Location.ID, byCircuitWith circuitID: Circuit.ID?, forShowWith showID: Show.ID?, atVenueWith venueID: Venue.ID?, detailsURL: URL?, scoresURL: URL?) async -> SingleResult<DrumKit.Event.ID> {
		await insert(
			EventInput(
				date: date, 
				detailsURL: detailsURL,
				scoresURL: scoresURL,
				locationID: locationID, 
				circuitID: circuitID, 
				showID: showID,
				venueID: venueID
			)
		)	
	}
}

// MARK: -
private extension Array {
	func chunked(into size: Int) -> [[Element]] {
		return stride(from: 0, to: count, by: size).map {
			Array(self[$0 ..< Swift.min($0 + size, count)])
		}
	}
}

// Initial check EPIC

// 2018-cabs-on-the-beach
// 2018-sounds-on-the-susequehanna
// 2018-barnum-festival-champions-on-parade
// 2018-precision-&-pageantry
// 2018-buccaneer-classic
// 2018-drum-corps-grand-prix
// 2018-drum-corps-an-american-tradition-dca-edition
// 2018-parade-of-champions
// 2018-march-of-champions
// 2018-drum-corps-luau
// 2018-eat-to-the-beat
// 2018-showdown-of-champions-2018
// 2018-drum-corps-expo
// 2018-big-sounds-in-motion
// 2018-fanfare-2018
// 2018-southern-showdown
// 2018-dca-prelims
// 2018-dca-finals
// 2018-alumni-spectacular
// 2018-carolina-gold-invitational
// 2018-saints-showcase
// 2018-drum-corps-united-kingdom-open-prelims
// 2018-drum-corps-united-kingdom-finals

// Add exhibitions from DCX that are not on DCI Scores as 0.0 (2013 – 2025)
// This is manual each time

// Check all numeric-suffixed show slugs
// Check all Innovations in Brass and American Traditions
