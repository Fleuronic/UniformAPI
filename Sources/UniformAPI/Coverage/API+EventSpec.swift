// Copyright © Fleuronic LLC. All rights reserved.

import Kanna
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Uniform
import struct DrumKit.Event
import struct DrumKit.Feature
import struct DrumKit.Location
import struct DrumKit.Circuit
import struct DrumKit.Show
import struct DrumKit.Venue
import struct DrumKit.Placement
import struct DrumKitService.IdentifiedEvent
import protocol Catena.ResultProviding
import protocol UniformService.EventSpec

extension API: EventSpec {
	public func listEvents(with urls: [URL]) async -> Results<EventSpecifiedFields> {
		guard !urls.isEmpty else { return .success([]) }

		let currentYear = Calendar.current.component(.year, from: .init())
		return await listEvents(for: currentYear, with: urls)
	}

	public func listEvents(for year: Int, with corpsRecord: ((String) async -> String)?) async -> Results<EventSpecifiedFields> {
		await listEvents(for: year, excluding: [], with: corpsRecord)
	}

	public func listEvents(for year: Int, excluding excludedURLs: Set<URL>, with corpsRecord: ((String) async -> String)?) async -> Results<EventSpecifiedFields> {
		let modifications = (try? await eventModifications(for: year)) ?? [:]
		let eventURLs = modifications.isEmpty ? nil : modifications.keys.sorted {
			$0.absoluteString < $1.absoluteString
		}

		return await listEvents(for: year, with: eventURLs, excluding: excludedURLs, modifications: modifications, with: corpsRecord)
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

	public func updateEvent(with eventID: DrumKit.Event.ID, on date: Date, inLocationWith locationID: Location.ID, byCircuitWith circuitID: Circuit.ID?, forShowWith showID: Show.ID?, atVenueWith venueID: Venue.ID?, detailsURL: URL?, scoresURL: URL?) async -> SingleResult<DrumKit.Event.ID> {
		await update(
			EventInput(
				date: date,
				detailsURL: detailsURL,
				scoresURL: scoresURL,
				locationID: locationID,
				circuitID: circuitID,
				showID: showID,
				venueID: venueID
			),
			with: eventID
		)
	}

	public func deleteEvents(with ids: [DrumKit.Event.ID]) async -> Results<DrumKit.Event.ID> {
		await delete(DrumKit.Event.Identified.self, with: ids)
	}
}

// MARK: -
private extension API {
	func eventModifications(for year: Int) async throws -> [URL: String] {
		guard year >= 2024 else { return [:] }

		let apiURL = URL(string: "https://www.dci.org/wp-json/wp/v2/event?per_page=100&orderby=modified&order=desc")!
		let (data, _) = try await scraperSession.data(from: apiURL)
		let events = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]

		let keys = events
			.compactMap { event -> (String, String)? in
				guard let link = event["link"] as? String, let modified = event["modified_gmt"] as? String else { return nil }
				return (link, modified)
			}
			.map { ($0.0.hasSuffix("/") ? String($0.0.dropLast()) : $0.0, $0.1) }
			.filter { $0.0.contains("/events/\(year)-") }
			.compactMap { link, modified in URL(string: link + "/").map { ($0, modified) } }

		return Dictionary(keys) { first, _ in first }
	}

	func listEvents(for year: Int, with urls: [URL]?, excluding excludedURLs: Set<URL> = [], modifications: [URL: String] = [:], with corpsRecord: ((String) async -> String)? = nil) async -> Results<EventSpecifiedFields> {
		var slugs: [String: Int] = [:]
		let formatStyle = Date.FormatStyle().month(.wide).day().year().locale(Locale(identifier: "en_US_POSIX"))

		do {
			var events: [EventSpecifiedFields] = []
			for index in 1...(urls?.count ?? 350) {
				let showID = String(format: "%03d", index)
				let id = Uniform.Event.ID(rawValue: Int(showID)!)
				let idRows: [String]
				let date: Date
				let location: EventSpecifiedFields.EventLocationFields?
				let show: EventSpecifiedFields.EventShowFields?
				let circuitName: String
				let detailsDoc: HTMLDocument?

				var scoresURL: URL?
				var prefetchedScoresHTML: String?
				if urls == nil {
					guard
						let url = URL(string: "https://www.dcxmuseum.org/show.cfm?view=show&ShowID=\(year)\(showID)"),
						case let html = try await scraperSession.string(from: url),
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
					circuitName = header[3].isEmpty ? (show?.name == "Sounds of Minnesota" ? "DCA" : "DCI") : header[3]
					detailsDoc = nil
				} else {
					let pendingEventURL = urls![index - 1]
					if excludedURLs.contains(pendingEventURL) { continue }

					let modification = modifications[pendingEventURL]
					if let cached = eventCache.event(at: pendingEventURL, modifiedBy: modification) as? EventSpecifiedFields {
						events.append(cached)
						continue
					}

					let eventSlug = pendingEventURL.lastPathComponent
					scoresURL = URL(string: "https://www.dci.org/scores/final-scores/\(eventSlug)/")

					if corpsRecord == nil {
						let (data, response) = try await scraperSession.data(from: scoresURL!)
						if (response as! HTTPURLResponse).statusCode == 404 { continue }
						prefetchedScoresHTML = String(decoding: data, as: UTF8.self)
					}

					idRows = []
					let html = try await scraperSession.string(from: pendingEventURL)
					detailsDoc = try? HTML(html: html, encoding: .utf8)

					guard
						let doc = detailsDoc,
						let showName = doc.xpath("//div[@class='inner-hero-inner']/h1").first?.text,
						let fullDateString = doc.xpath("//div[@class='inner-hero-inner']/p").first?.text,
						let fullLocationString = doc.xpath("//span[@class='location']").first?.text else { continue }

					let dateString = fullDateString
						.components(separatedBy: " ")
						.dropFirst()
						.prefix(3)
						.joined(separator: " ")
						.trimmingCharacters(in: .whitespacesAndNewlines)
					let locationString = fullLocationString.trimmingCharacters(in: .whitespacesAndNewlines)
					date = try! Date(dateString, strategy: formatStyle.parseStrategy)

					let startOfDate = Calendar.current.startOfDay(for: date)
					let currentDate = Date(timeIntervalSince1970: Date().timeIntervalSince1970)
					let startOfCurrentDate = Calendar.current.startOfDay(for: currentDate)

					if startOfDate > startOfCurrentDate { scoresURL = nil }

					location = EventSpecifiedFields.EventLocationFields(name: locationString)
					show = EventSpecifiedFields.EventShowFields(name: showName, city: location?.city, year: year)
					circuitName = "DCI"

					if scoresURL == nil {
						let slug = eventSlug.components(separatedBy: "-").dropFirst().joined(separator: "-")
						let scoreSlug = Show.scoreSlug(for: slug, in: location?.city, year: year)
						scoresURL = scoresURL.map { _ in URL(string: "https://www.dci.org/scores/final-scores/\(year)-\(scoreSlug)/")! }
					}
				}

				guard
					/* Year from date matches year */
					Show.isValid(with: show?.name) else { continue }

				let detailsURL: URL?
				if let urls {
					detailsURL = urls[index - 1]
				} else {
					let slug = (show?.name).flatMap { Show.slug(forShowNamed: $0, in: year) }
					if let slug, circuitName == "DCI" {
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
				}

				let scoresHTML: String?
				if let scoresURL {
					if let prefetchedScoresHTML {
						scoresHTML = prefetchedScoresHTML
					} else {
						scoresHTML = try? await scraperSession.string(from: scoresURL)
					}
				} else {
					scoresHTML = nil
				}

				let scoreRows: [String]? = if
					let scoresHTML,
					let doc = try? HTML(html: scoresHTML, encoding: .utf8) {
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
				let circuit = EventSpecifiedFields.EventCircuitFields(name: scoreRows == nil ? (circuitName == "SoundSport" ? "DCI" : circuitName) : "DCI")

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

				let detailsHTML: String?
				if detailsDoc == nil, let detailsURL {
					detailsHTML = try? await scraperSession.string(from: detailsURL)
				} else {
					detailsHTML = nil
				}
				if
					let detailsURL,
					let doc = detailsDoc ?? detailsHTML.flatMap({ try? HTML(html: $0, encoding: .utf8) }),
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
						case ("0", 2026): "St. Joe’s of Batavia Brass Ensemble - Batavia, NY"
						case ("0", 2019): "EPIC Percussion Junior Cadets - Williamsport, PA"
						default: await corpsRecord!(id)
						}

						let name = record.components(separatedBy: " - ")[0]
						if !corps.contains(name) {
							records.append(record)
							let index = idRows
								.enumerated()
								.filter { $0.element == id && $0.offset % multiple == initial }
								.last!
								.offset

							let divisionName = show.flatMap { $0.name.contains("Mini") ? "Mini-Corps" : nil } ?? (idRows[index - 2].isEmpty ? (circuitName == "SoundSport" ? "SoundSport Medalist Division" : (circuit.abbreviation == "DCA" ? "Open" : "World")) : idRows[index - 2])
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
						let record = await corpsRecord!(corps)
						if record.contains(" ,") || record.hasSuffix(" ") { fatalError() }
						slotRows += ["", record]
					}

					addressComponents = []
					timeZone = "GMT"
				}

				let venueName: String? = if addressComponents.count == 3 && addressComponents[1] != "TBA" {
					addressComponents[0]
				} else {
					nil
				}

				let venue = venueName.map { name in
					EventSpecifiedFields.EventVenueFields(
						name: venueName ?? "",
						address: EventSpecifiedFields.EventVenueFields.VenueAddressFields(
							records: addressComponents.suffix(2)
						)
					)
				}

				let chunks = slotRows.chunked(into: 2)
				let hasTimes = chunks.allSatisfy { !$0[0].isEmpty }

				let timedGroups: Set<String> = Set(chunks.compactMap { row in
					let time = row[0]
					guard !time.isEmpty else { return nil }
					let record = row[1].components(separatedBy: " - ")[0]
					guard Feature.name(for: record) == nil else { return nil }
					return Placement.groupName(for: record)
				})

				let slots = chunks.compactMap { row -> EventSpecifiedFields.EventSlotFields? in
					let time = row[0]
					let name = row[1]
					let record = name.components(separatedBy: " - ")[0]
					let groupName = Placement.groupName(for: record)

					let slot = EventSpecifiedFields.EventSlotFields(
						time: time,
						name: name,
						placement: placements[groupName],
						isPotentiallyEncore: hasTimes
					)

					if slot.feature == nil && hasTimes && time.isEmpty { return nil }
					if slot.feature == nil && time.isEmpty && timedGroups.contains(groupName) { return nil }

					return slot
				}

				let event = EventSpecifiedFields(
					id: id,
					date: date,
					detailsURL: detailsURL,
					scoresURL: validScoresURL,
					timeZone: timeZone,
					location: location,
					circuit: circuit,
					show: show,
					venue: venue,
					slots: slots
				)

				if let event {
					// print(event)
					events.append(event)
					if let urls {
						let modification = modifications[urls[index - 1]]
						eventCache.store(event, at: urls[index - 1], modification: modification)
					}
				}
			}

			return .success(events)
		} catch {
			return .failure(.network(error as NSError))
		}
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

// MARK: -
private let eventCache = EventCache()

private final class EventCache: @unchecked Sendable {
	private let lock = NSLock()
	private var entries: [URL: (modification: String, event: Any)] = [:]

	func event(at url: URL, modifiedBy modification: String?) -> Any? {
		guard let modification else { return nil }

		lock.lock()
		defer { lock.unlock() }

		let entry = entries[url]
		return entry?.modification == modification ? entry?.event : nil
	}

	func store(_ event: Any, at url: URL, modification: String?) {
		guard let modification else { return }

		lock.lock()
		defer { lock.unlock() }

		entries[url] = (modification, event)
	}
}

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

// Add exhibitions from DCX that are not on DCI Scores as 0.0 (2013 – 2026)
// This is manual each time

// Check all numeric-suffixed show slugs
// Check all Innovations in Brass and American Traditions
