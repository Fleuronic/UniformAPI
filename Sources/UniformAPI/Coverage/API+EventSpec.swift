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
			for index in 1...71 {
				let showID = String(format: "%03d", index)
				let id = Uniform.Event.ID(rawValue: Int(showID)!)
				let idRows: [String]
				let date: Date
				let location: EventSpecifiedFields.EventLocationFields?
				let show: EventSpecifiedFields.EventShowFields?
				let circuitName: String
				if year < 2026 {
					guard
						let url = URL(string: "https://www.dcxmuseum.org/show.cfm?view=show&ShowID=\(year)\(showID)"),
						case let html = try String(contentsOf: url, encoding: .utf8),
						let doc = try? HTML(html: html, encoding: .utf8),
						let header = (doc.xpath("//th[1]")
							.first?
							.innerHTML?
							.components(separatedBy: "<br>")
							.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
						!header[2].isEmpty, !header[2].contains("Online") else { continue }
					idRows = doc.xpath("//td")
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
					date = try! Date(header[1], strategy: formatStyle.parseStrategy)
					location = EventSpecifiedFields.EventLocationFields(name: header[2])
					show = EventSpecifiedFields.EventShowFields(name: header[0], city: location?.city, year: year)
					circuitName = header[3]
				} else {
					idRows = []
					let pendingEvent = pending[index - 1]
					date = try! Date(pendingEvent.1, strategy: formatStyle.parseStrategy)
					location = EventSpecifiedFields.EventLocationFields(name: pendingEvent.2)
					show = EventSpecifiedFields.EventShowFields(name: pendingEvent.0, city: location?.city, year: year)
					circuitName = "DCI"
				}

				guard
					/* Year from date matches year */
					Show.isValid(with: show?.name) else { continue }

				let detailsURL: URL?
				let scoresURL: URL?
				let slug = (show?.name).flatMap { Show.slug(forShowNamed: $0, in: year) }
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
				let circuit = EventSpecifiedFields.EventCircuitFields(name: scoreRows == nil ? circuitName : "DCI")

				let validScoresURL: URL?
				if let scoreRows {
					validScoresURL = scoresURL
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
				} else {
					validScoresURL = nil
				}

				var slotRows: [String] = []
				let addressComponents: [String]
				let timeZone: String
				let validDetailsURL: URL?

				if
					let detailsURL,
					let html = try? String(contentsOf: detailsURL, encoding: .utf8),
					let doc = try? HTML(html: html, encoding: .utf8),
					let tableHeader = doc.xpath("//div[@class='lineup-times-table']/div/p").first?.text {
					slotRows = (doc.xpath("//div[@class='table-responsive common-table']/table/tbody[1]")
						.first?
						.xpath("//td")
						.compactMap(\.text)) ?? []
					addressComponents = (doc.xpath("//address")
						.first!
						.innerHTML!
						.components(separatedBy: "<br>")
						.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
						.filter { !$0.isEmpty })
					timeZone = tableHeader.components(separatedBy: " ")[2]
					validDetailsURL = detailsURL
				} else {
					let corps = placements.keys + exhibitionCorps
					let hasPictures =
						idRows.count > 10 && idRows[10] == "0" ||
						idRows.count > 60 && idRows[60] == "0" ||
						idRows.count > 180 && idRows[180] == "0" ||
						idRows[0] == "0"
					let (initial, multiple) = hasPictures ? (3, 5) : (2, 4)
					let ids = stride(from: initial, through: idRows.count - 1, by: multiple).map { idRows[$0] }

					var records: [String] = []

					for id in ids where !id.isEmpty && !id.contains("-") && id != "99999" {
						let record = switch(id, year) {
						case ("0", 2025): "St. Joe’s of Batavia Brass Ensemble - Batavia, NY"
						case ("0", 2019): "EPIC Percussion Junior Cadets - Williamsport, PA"
						default: await corpsRecord(id)
						}

						let name = record.components(separatedBy: " - ")[0]
						if !corps.contains(name) {
							records.append(record)
							let index = idRows
								.enumerated()
								.filter { $0.element == id && $0.offset % multiple == initial }
								.last!
								.offset

							let divisionName = show.flatMap { $0.name.contains("Mini") ? "Mini-Corps" : nil } ?? idRows[index - 2]
							let circuitAbbreviation = Circuit.abbreviation(forDivisionNamed: divisionName) ?? circuit.abbreviation
							if let rank = Int(idRows[index - 1]), let score = Double(idRows[index + 1]) {
								placements[name] = .init(
									rank: rank,
									score: score,
									divisionName: divisionName.isEmpty ? nil : divisionName,
									circuitAbbreviation: circuitAbbreviation
								)
							}
						}
					}

					for record in records {
						if record.contains(" ,") || record.hasSuffix(" ") { fatalError() }
						if !slotRows.contains(record) {
							slotRows += ["", record]
						}
					}

					for corps in corps {
						let record = await corpsRecord(corps)
						if record.contains(" ,") || record.hasSuffix(" ") { fatalError() }
						slotRows += ["", record]
					}

					addressComponents = []
					timeZone = "GMT"
					validDetailsURL = nil
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
					detailsURL: validDetailsURL,
					scoresURL: validScoresURL,
					timeZone: timeZone,
					location: location,
					circuit: circuit,
					show: show,
					venue: venue,
					slots: slots
				)

				if let event {
					// events.append(event)
					// print(slots)
					print(event)
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

private let pending = [
	("DCI Tour Preview", "June 26, 2026", "Muncie, IN"),
	("Barnum Festival: Champions on Parade", "June 27, 2026", "Shelton, CT"),
	// ("Bluecoats Opening Night Community Celebration", "June 27, 2026", "Alliance, OH"),
	("Drums Along the Rockies", "June 27, 2026", "Fort Collins, CO"),
	("Corps Encore", "June 28, 2026", "Ogden, UT"),
	("Northwest Youth Music Games Seattle", "June 30, 2026", "Seattle, WA"),
	("Drums Along the Columbia", "June 29, 2026", "Kennewick, WA"),
	("Northwest Youth Music Games Portland", "July 1, 2026", "Portland, OR"),
	("Drums Across Nebraska", "July 1, 2026", "Omaha, NE"),
	("Rotary Music Festival", "July 2, 2026", "Cedarburg, WI"),
	("MidCal Championships", "July 2, 2026", "Oxnard, CA"),
	("Show of Shows", "July 3, 2026", "Rockford, IL"),
	("DCI Capital Classic", "July 3, 2026", "Sacramento, CA"),
	("DCI West", "July 5, 2026", "Stanford, CA"),
	("River City Rhapsody", "July 5, 2026", "La Crosse, WI"),
	("Drums Across the Smokies", "July 7, 2026", "Sevierville, TN"),
	("The Kiwanis Thunder of Drums", "July 7, 2026", "Mankato, MN"),
	("Drums Across America", "July 8, 2026", "Newnan, GA"),
	("Celebration in Brass", "July 8, 2026", "Ankeny, IA"),
	("Gold Showcase", "July 9, 2026", "Santa Clarita, CA"),
	("DCI Northern Alabama", "July 9, 2026", "Muscle Shoals, AL"),
	("Cavalcade of Brass", "July 10, 2026", "Lisle, IL"),
	("Music on the March", "July 10, 2026", "Dubuque, IA"),
	("Western Corps Connection", "July 10, 2026", "Walnut, CA"),
	("Drum Corps Grand Prix", "July 11, 2026", "Clifton, NJ"),
	("The Whitewater Classic", "July 11, 2026", "Whitewater, WI"),
	("DCI Little Rock", "July 11, 2026", "Little Rock, AR"),
	("Drum Corps at the Rose Bowl", "July 11, 2026", "Pasadena, CA"),
	("So Cal Classic: Open Class Pacific Championship Finals", "July 12, 2026", "Buena Park, CA"),
	("Brass Impact", "July 13, 2026", "Olathe, KS"),
	("Drums Across the Desert", "July 13, 2026", "Mesa, AZ"),
	("DCI Broken Arrow", "July 14, 2026", "Broken Arrow, OK"),
	("DCI Hutchinson", "July 14, 2026", "Hutchinson, KS"),
	("DCI New Mexico", "July 14, 2026", "Albuquerque, NM"),
	("DCI Central Texas", "July 16, 2026", "Central, TX"),
	("DCI Denton", "July 16, 2026", "Denton, TX"),
	("DCI Houston", "July 17, 2026", "Houston, TX"),
	("DCI Southwestern Championship", "July 18, 2026", "San Antonio, TX"),
	("The Buccaneer Classic", "July 18, 2026", "Landisville, PA"),
	("DCI Dallas", "July 19, 2026", "Bedford, TX"),
	("DCI McKinney", "July 20, 2026", "McKinney, TX"),
	("DCI St. Louis", "July 21, 2026", "Belleville, IL"),
	("Drums on the Ohio", "July 22, 2026", "Evansville, IN"),
	("March On!", "July 22, 2026", "Champlin, MN"),
	("DCI Southern Mississippi", "July 22, 2026", "Hattiesburg, MS"),
	("DCI Syracuse", "July 24, 2026", "Central New York, NY"),
	("Drums on Parade", "July 24, 2026", "Madison, WI"),
	("DCI Birmingham", "July 24, 2026", "Birmingham, AL"),
	("DCI Nashville", "July 24, 2026", "Nashville, TN"),
	("DCI Southeastern Championship", "July 25, 2026", "Atlanta, GA"),
	("Bushwackers Invitational", "July 25, 2026", "Mt. Olive, NJ"),
	("Music on the Mountain", "July 25, 2026", "Sheffield, PA"),
	("Midwestern Championship", "July 26, 2026", "DeKalb, IL"),
	("NightBEAT", "July 26, 2026", "Winston-Salem, NC"),
	("DCI in Motion", "July 26, 2026", "Norton, OH"),
	("Summer Music Games in Cincinnati", "July 28, 2026", "Mason, OH"),
	("DCI Annapolis", "July 28, 2026", "Annapolis, MD"),
	("Brass at the Beach", "July 28, 2026", "Myrtle Beach, SC"),
	("Summer Music Games of Southwest Virginia", "July 29, 2026", "Salem, VA"),
	("DCI Huntington", "July 29, 2026", "Huntington, WV"),
	("The Marion Open", "July 30, 2026", "Marion, OH"),
	("DCI East Coast Showcase", "July 30, 2026", "Lawrence, MA"),
	("DCI Eastern Classic", "July 31, 2026", "Allentown, PA"),
	("DCI Michigan", "July 31, 2026", "Allendale, MI"),
	("DCI Eastern Classic", "August 1, 2026", "Allentown, PA"),
	("Big Sounds in Motion", "August 2, 2026", "Downingtown, PA"),
	("DCI World Championship Prelims", "August 6, 2026", "Indianapolis, IN"),
	("Innovations In Brass", "August 3, 2026", "Northeast, OH"),
	("DCI All-Age World Championship Prelims", "August 7, 2026", "Indianapolis, IN"),
	("DCI World Championship Semifinals", "August 7, 2026", "Indianapolis, IN"),
	("DCI All-Age World Championship Finals", "August 8, 2026", "Indianapolis, IN"),
	("DCI World Championship Finals", "August 8, 2026", "Indianapolis, IN")
]

// 2018-cabs-on-the-beach
// 2018-sounds-on-the-susquehanna
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
