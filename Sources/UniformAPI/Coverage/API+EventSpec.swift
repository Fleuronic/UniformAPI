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
			for index in 104...104 {
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

				let idRows = doc.xpath("//td")
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
					let ids: [String]
					let corps = placements.keys + exhibitionCorps

					let hasPictures = idRows[0] == "0"
					if hasPictures {
						ids = stride(from: 3, through: idRows.count - 1, by: 5).map { idRows[$0] }
					} else {
						ids = stride(from: 2, through: idRows.count - 1, by: 4).map { idRows[$0] }
					}

					var records: [String] = []
					for id in ids {
						let record = await corpsRecord(id)
						let name = record.components(separatedBy: " - ")[0]
						if !corps.contains(name) {
							records.append(record)
							let index = idRows.firstIndex(of: id)!
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
					timeZone: timeZone,
					location: location,
					circuit: circuit,
					show: show,
					venue: venue,
					slots: slots
				)

				if circuit.abbreviation == "DCA" {
					print(location)
					// print(slots)
					if let event {
						events.append(event)
					}
				}
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

// MARK: -
private extension Array {
	func chunked(into size: Int) -> [[Element]] {
		return stride(from: 0, to: count, by: size).map {
			Array(self[$0 ..< Swift.min($0 + size, count)])
		}
	}
}

// 2023-barnum-festival
// 2023-grand-prix
// 2023-the-classic
// 2023-dca-williamsport
// 2023-saints-showcase
// 2023-bushwackers-invitational
// 2023-big-sounds-in-motion
// 2023-fanfare
// 2023-mini-corps-championships
// 2023-dca-world-championship-prelims
// 2023-alumni-spectacular
// 2023-dca-world-championship-finals
// 2023-drum-corps-an-american-tradition-annapolis
// 2023-white-sabers-friends-and-family

// 2022-barnum-festival-champions-on-parade
// 2022-drum-corps-grand-prix
// 2022-the-classic
// 2022-dca-williamsport
// 2022-march-of-champions
// 2022-dca-mount-olive
// 2022-fanfare-thunder-in-the-valley
// 2022-dca-world-championships-mini-corps-&-i&e
// 2022-dca-world-championships-prelims
// 2022-dca-world-championships-alumni-spectacular
// 2022-dca-world-championships-finals

// 2019-cabs-at-the-beach
// 2019-sounds-on-the-susequehanna
// 2019-barnum-festival-champions-on-parade
// 2019-buccaneer-classic
// 2019-drum-corps-grand-prix
// 2019-saints-showcase
// 2019-long-island-evening-with-the-corps
// 2019-parade-of-champions
// 2019-drum-corps-expo
// 2019-march-of-champions
// 2019-bush-at-the-bridge
// 2019-carolina-gold-invitational
// 2019-big-sounds-in-motion
// 2019-fanfare-thunder-in-the-valley
// 2019-southern-showdown
// 2019-dca-prelims
// 2019-alumni-spectacular
// 2019-dca-finals

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

// 2017-cabs-at-the-beach
// 2017-an-evening-with-the-corps
// 2017-red,-white-and-brass
// 2017-precision-and-pageantry
// 2017-drum-corps-grand-prix
// 2017-drum-corps-an-american-tradition,-dca-edition
// 2017-parade-of-champions
// 2017-drum-corps-luau
// 2017-march-of-champions
// 2017-the-marching-millionaires-dca-invitational
// 2017-drum-corps-expo
// 2017-bushwacker-invitational
// 2017-sounds-of-minnesota
// 2017-big-sounds-in-motion
// 2017-fanfare-2017
// 2017-southern-showdown
// 2017-dca-championship-preliminaries
// 2017-dca-championship-finals
// 2017-dca-alumni-spectacular
// 2017-dmg-contest-roosendaal
// 2017-dcuk-contest-barnsley
// 2017-dmg-contest-huizen
// 2017-fanfare

// 2016-cabs-at-the-beach
// 2016-an-evening-with-the-corps
// 2016-red,-white-and-brass
// 2016-precision-and-pageantry
// 2016-grand-prix
// 2016-ost--type-keywords--drum-corps-an-american-tradition%E2%80%A6-dca-edition
// 2016-tournament-of-stars
// 2016-downingtown-classic
// 2016-kiltie-klassic-invitational
// 2016-dca-woodstock-peace,-love,-drum-corps
// 2016-turning-point-invitational
// 2016-the-marching-millionaires-dca-invitational
// 2016-sounds-of-minnesota
// 2016-drum-corps-expo
// 2016-the-everett-drum-&-bugle-corps-show
// 2016-parade-of-champions
// 2016-southern-showdown
// 2016-fanfare-2016
// 2016-big-sounds-in-motion
// 2016-dca-championship-preliminaries
// 2016-dca-championship-finals
// 2016-alumni-spectacular
// 2016-march-of-champions
// 2016-drum-corps-europe-championships-finals
// 2016-drum-corps-europe-championships-prelims
// 2016-drum-corps-europe-championships-finals-2

// 2015-drum-corps-an-american-tradition-annapolis
// 2015-2nd-annual-street-beat-5k
// 2015-cabs-at-the-beach
// 2015-champions-on-parade
// 2015-carolina-gold-southern-classic
// 2015-grand-prix
// 2015-kiwanis-open
// 2015-downingtown-classic
// 2015-tournament-of-stars
// 2015-kiltie-klassic-invitational
// 2015-dca-woodstock-peace,-love,-drum-corps
// 2015-parade-of-champions
// 2015-southern-showdown
// 2015-2015-championship-preview
// 2015-drum-corps-expo
// 2015-big-sounds-in-motion
// 2015-fanfare-2015
// 2015-dca-championship-preliminaries
// 2015-alumni-spectacular
// 2015-sounds-of-minnesota
// 2015-turning-point-invitational
// 2015-dca-championship-finals

// 2014-cabs-at-the-beach
// 2014-tournament-of-stars
// 2014-champions-on-parade
// 2014-state-of-the-art-drum-corps-invitational
// 2014-drum-corps-grand-prix
// 2014-kiwanis-open
// 2014-carolina-gold-southern-classic
// 2014-dca-peace,-love,-and-drum-corps
// 2014-downingtown-classic
// 2014-march-of-champions
// 2014-the-kiltie-klassic-invitational
// 2014-turning-point-invitational
// 2014-bushwacker-invitational
// 2014-sounds-of-minnesota
// 2014-southern-showdown
// 2014-parade-of-champions
// 2014-drum-corps-expo
// 2014-big-sounds-in-motion
// 2014-fanfare-2014
// 2014-dca-championship-preliminaries
// 2014-drum-corps-competition
// 2014-dca-world-championship-finals
// 2014-alumni-spectacular

// 2013-cabs-at-the-beach
// 2013-champions-on-parade
// 2013-cavalcade-of-champions
// 2013-drum-corps-grand-prix
// 2013-mission-drums
// 2013-downingtown-classic
// 2013-parade-of-champions
// 2013-big-sounds-in-motion
// 2013-dca-championship-preliminaries
// 2013-alumni-spectacular
// 2013-dca-world-championship-finals
// 2013-sound-of-the-south
// 2013-music-under-the-stars
// 2013-march-of-champions
// 2013-kiltie-klassic-invitational
// 2013-state-of-the-art-nature-coast-drum-corps-invitational
// 2013-turning-point-invitational
// 2013-bushwacker-invitational
// 2013-sounds-of-minnesota
// 2013-drum-corps-expo
// 2013-southern-showdown
// 2013-fanfare-2013
// 2013-pensauken-invitational

// Add exhibitions from DCX that are not on DCI Scores as 0.0 (2013 – 2025)
// This is manual each time

// Check all numeric-suffixed show slugs
