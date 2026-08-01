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
import struct DrumKit.Division
import struct DrumKitService.IdentifiedEvent
import protocol Catena.ResultProviding
import protocol UniformService.EventSpec

// MARK: -
extension API {
	// The season's DCI event-page URLs, straight from the wp-json events feed (a Sep–Sep
	// window). Only wp-json years (2024+) have this; earlier years come from the museum.
	// Both a "<slug>" and its two-day "<slug>-2" sibling appear here when present.
	func eventURLs(for year: Int) async throws -> [URL] {
		guard year >= 2024 else { return [] }

		let apiURL = URL(string: "https://www.dci.org/wp-json/wp/v2/event?per_page=100&_fields=link&after=\(year - 1)-09-01T00:00:00&before=\(year)-09-01T00:00:00")!
		let data = try await scraperSession.solvedData(from: apiURL)
		guard let events = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
			let preview = String(decoding: data.prefix(200), as: UTF8.self)
			print("wp-json did not return a JSON array (\(data.count) bytes): \(preview)")
			return []
		}

		let links = events
			.compactMap { $0["link"] as? String }
			.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
			.filter { $0.contains("/events/\(year)-") && !$0.contains("education") }
			.compactMap { URL(string: $0 + "/") }

		let urls = Array(Set(links)).sorted { $0.absoluteString < $1.absoluteString }
		print("wp-json: \(events.count) events -> \(urls.count) \(year) event URLs")
		return urls
	}

	// Scrapes a season's events into `EventSpecifiedFields` from one of two sources:
	//   • `urls != nil` — current DCI events (dci.org wp-json event pages + recap scores).
	//   • `urls == nil` — historical events from the mpamdcx.org museum (probed by ShowID).
	// Orthogonally, two run modes share this body:
	//   • LIVE / current      (`corpsRecord == nil`): polling for scores as they post.
	//   • RECORDED / backfill (`corpsRecord != nil`): reconciling already-finished events.
	// A thrown error (e.g. the solver couldn't clear Cloudflare) fails the WHOLE sweep rather
	// than reporting partial data as truth, since callers prune events missing from the result.
	func listEvents(for year: Int, with urls: [URL]?, excluding excludedURLs: Set<URL> = [], excludingScoresFor scoresExcludedURLs: Set<URL> = [], with corpsRecord: ((String) async -> String)? = nil) async -> Results<EventSpecifiedFields> {
		// Per-show-name counter for the museum path, where repeats get "-2", "-3", … suffixes.
		var slugs: [String: Int] = [:]
		let loadingCurrentEvents = corpsRecord == nil
		// "Month D, YYYY" (e.g. "August 1, 2026"): parses details-page dates AND matches recap pages.
		let formatStyle = Date.FormatStyle().month(.wide).day().year().locale(Locale(identifier: "en_US_POSIX"))
		// Every event slug this season, so a two-day event's "-2" sibling can be detected.
		let slugSet = Set((urls ?? []).map(\.lastPathComponent))

		do {
			var events: [EventSpecifiedFields] = []
			// wp-json gives an exact URL list; the museum is probed by sequential ShowID.
			for index in 1...(urls?.count ?? 999) {
				let showID = String(format: "%03d", index)
				let id = Uniform.Event.ID(rawValue: Int(showID)!)

				// Per-event "basics", filled in by whichever source branch runs below.
				let idRows: [String]           // museum: cell text used to reconstruct placements
				let date: Date
				let location: EventSpecifiedFields.EventLocationFields?
				let show: EventSpecifiedFields.EventShowFields?
				let circuitName: String
				let detailsDoc: HTMLDocument?  // wp-json: parsed details page, reused for the lineup

				var scoresURL: URL?
				var recapURL: URL?
				var prefetchedScoresHTML: String?  // wp-json/live: recap HTML fetched during resolution
				var hasPhotoColumn = false         // museum: shifts the idRows stride

				// ===== SOURCE A: museum (mpamdcx.org) — historical events, no wp-json URL. =====
				if urls == nil {
					// The header cell is "<show><br><date><br><location><br><circuit>"; bail on a
					// blank/online-only show (and on BYBA, which isn't a real competitive event).
					guard
						let url = URL(string: "https://mpamdcx.org/show.cfm?view=show&ShowID=\(year)\(showID)"),
						case let html = try await scraperSession.string(from: url),
						let doc = try? HTML(html: html, encoding: .utf8),
						let header = (doc.xpath("//th[1]")
							.first?
							.innerHTML?
							.components(separatedBy: "<br>")
							.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
						!header[2].isEmpty, !header[2].contains("Online") else { continue }

					if header[3].contains("BYBA") { continue }

					// Each data cell is either a corps-id link (take the id) or plain text.
					idRows = doc.xpath("//td[not(@colspan)]")
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
					hasPhotoColumn = doc.xpath("//th").contains {
						($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "Photos"
					}

					// Map the header cells onto the event basics; circuit falls back to DCI (or DCA
					// for the one Minnesota exception) when the header names none.
					date = try! Date(header[1], strategy: formatStyle.parseStrategy)
					location = EventSpecifiedFields.EventLocationFields(name: header[2])
					show = header[0].uppercased() == "EXHIBITION" ? nil : EventSpecifiedFields.EventShowFields(name: header[0], city: location?.city, year: year)
					circuitName = header[0].contains("IMBA") ? "IMBA" : (header[3].isEmpty ? (show?.name == "Sounds of Minnesota" ? "DCA" : "DCI") : header[3])
					detailsDoc = nil
					// ===== SOURCE B: current DCI (dci.org) — one wp-json event page per URL. =====
				} else {
					let pendingEventURL = urls![index - 1]
					if excludedURLs.contains(pendingEventURL) { continue }

					let eventSlug = pendingEventURL.lastPathComponent

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

					// Resolve which recap page holds THIS event's scores. Normally that's the
					// event's own slug — but a two-day event at one venue gets a base slug and a
					// "<slug>-2" sibling, and DCI doesn't keep the event-page slug aligned with the
					// recap slug across the two days (2026 Allentown had them reversed). So when a
					// sibling exists, try both and accept only the recap whose page reports this
					// event's date. The solver returns 200 for a not-yet-posted recap, so this
					// date match — not HTTP status — is what distinguishes the two nights.
					let siblingSlug = eventSlug.hasSuffix("-2") ? String(eventSlug.dropLast(2)) : eventSlug + "-2"
					let recapSlugs = slugSet.contains(siblingSlug) ? [eventSlug, siblingSlug] : [eventSlug]

					for slug in recapSlugs {
						guard let candidate = URL(string: "https://www.dci.org/scores/recap/\(slug)/") else { continue }
						if loadingCurrentEvents {
							// LIVE: fetch now and cache the HTML; for a paired event require a date match.
							guard
								case let (data, response) = try await scraperSession.data(from: candidate),
								(response as! HTTPURLResponse).statusCode != 404 else { continue }

							let recapHTML = String(decoding: data, as: UTF8.self)
							if recapSlugs.count > 1, !Self.recap(recapHTML, reports: date, using: formatStyle) { continue }

							prefetchedScoresHTML = recapHTML
							recapURL = candidate
							break
						} else if recapSlugs.count > 1 {
							// RECORDED + paired: the page slug can name the other day's recap, so accept
							// only the sibling whose recap page reports this event's own date.
							guard
								let recapHTML = try? await scraperSession.string(from: candidate),
								Self.recap(recapHTML, reports: date, using: formatStyle) else { continue }

							recapURL = candidate
							break
						} else {
							// RECORDED + unpaired: slug is unambiguous; fetch the scores lazily later.
							recapURL = candidate
							break
						}
					}

					// LIVE with no matching recap => scores not posted yet; skip and retry next poll.
					// (Recorded proceeds without scores rather than dropping the event.)
					if loadingCurrentEvents, recapURL == nil { continue }

					// The stored scores URL is the recap's final-scores counterpart.
					scoresURL = recapURL.flatMap { URL(string: $0.absoluteString.replacingOccurrences(of: "/recap/", with: "/final-scores/")) }

					// Never attach scores to a future event, or one the caller opted out of.
					let startOfDate = Calendar.current.startOfDay(for: date)
					let currentDate = Date(timeIntervalSince1970: Date().timeIntervalSince1970)
					let startOfCurrentDate = Calendar.current.startOfDay(for: currentDate)

					if startOfDate > startOfCurrentDate || scoresExcludedURLs.contains(pendingEventURL) { scoresURL = nil }

					location = EventSpecifiedFields.EventLocationFields(name: locationString)
					show = EventSpecifiedFields.EventShowFields(name: showName, city: location?.city, year: year)
					circuitName = "DCI"
				}

				// Skip anything that isn't a recognized show (exhibitions, non-events, etc.).
				guard Show.isValid(with: show?.name) else { continue }

				// Details URL: wp-json already has it; the museum derives it from the show slug
				// (and, for DCI shows, also derives the recap/final-scores URLs by era).
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
						recapURL = year >= 2013 ? .init(string: "https://www.dci.org/scores/recap/\(year)-\(scoreSlug)/") : nil
						scoresURL = recapURL.flatMap { URL(string: $0.absoluteString.replacingOccurrences(of: "/recap/", with: "/final-scores/")) }
					} else {
						detailsURL = nil
						scoresURL = nil
					}
				}

				var slotRows: [String] = []
				var addressComponents: [String] = []
				var timeZone = "GMT"

				// wp-json already parsed the details page into `detailsDoc`; the museum path
				// (no detailsDoc) fetches the derived DCI details page now, if there is one.
				let detailsHTML: String?
				if detailsDoc == nil, let detailsURL {
					detailsHTML = try? await scraperSession.string(from: detailsURL)
				} else {
					detailsHTML = nil
				}

				// A lineup page yields the schedule rows, the venue address, and the time zone.
				let hasLineup: Bool
				if
					detailsURL != nil,
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
					hasLineup = true
				} else {
					hasLineup = false
				}

				// RECORDED-only guard: don't attach scores to a finished event whose own lineup
				// never shows a score-announcement feature (it likely didn't award scores).
				if !loadingCurrentEvents, scoresURL != nil, hasLineup, !slotRows.chunked(into: 2).contains(where: { row in
					guard row.count == 2 else { return false }

					let record = row[1].components(separatedBy: " - ")[0]
					return Feature.name(for: record).map(isPossibleScoreAnnouncement) ?? false
				}) {
					scoresURL = nil
				}

				// Scores HTML: live already cached it during resolution; recorded fetches it now
				// (only if the guards above left a scoresURL standing).
				let scoresHTML: String?
				if let prefetchedScoresHTML {
					scoresHTML = prefetchedScoresHTML
				} else if let scoresURL {
					// wp-json events read from the recap page; museum events only have final-scores.
					scoresHTML = try? await scraperSession.string(from: recapURL ?? scoresURL)
				} else {
					scoresHTML = nil
				}

				// Placement rows from whichever scores page we fetched (recap or final-scores).
				let scoreRows = scoresHTML.flatMap { Self.scoreRows(fromScores: $0) }

				// Turn score rows into placements keyed by performing-group name. A bare row
				// (no leading rank) is a division heading; a score of 0 marks an exhibition.
				var divisionName: String? = nil
				var exhibitionCorps: [String] = []
				var placements: [String: EventSpecifiedFields.EventSlotFields.SlotPlacementFields] = [:]
				let circuit = EventSpecifiedFields.EventCircuitFields(name: scoreRows == nil ? (circuitName == "SoundSport" ? "DCI" : circuitName) : "DCI")

				// `validScoresURL` is stored only when a table actually parsed from the page.
				let validScoresURL: URL?
				if let scoreRows {
					validScoresURL = scoresURL
					for row in scoreRows {
						let components = row.components(separatedBy: " ")
						let rank = Int(components[0])
						// A leading integer marks a placement row; otherwise it's a division heading.
						if let rank {
							let corps = components.dropFirst().dropLast().joined(separator: " ")
							let score = Double(components.last!)!

							if score > 0 {
								placements[corps] = .init(
									rank: rank,
									score: score,
									circuit: circuit,
									division: EventSpecifiedFields.EventSlotFields.SlotPlacementFields.PlacementDivisionFields(
										name: divisionName!,
										circuit: circuit
									)
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

				// Museum events have no lineup page, so per-corps records and placements are
				// reconstructed from the flat idRows table: fixed-stride columns (wider when a
				// Photos column is present) hold each corps' id, rank, and score.
				if !hasLineup {
					let corps = placements.keys + exhibitionCorps
					let (initial, multiple) = hasPhotoColumn ? (3, 5) : (2, 4)
					let ids = stride(from: initial, through: idRows.count - 1, by: multiple).map { idRows[$0] }

					var records: [String] = []

					for id in ids where !id.isEmpty && !id.contains("-") && !["99999", "14827"].contains(id) {
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

							// Division name comes from the table (or is inferred from the show name),
							// then normalized to the era's naming (1992–2007 "* Division" labels and
							// circuit-specific All-Age/Junior/Senior renames).
							let rawDivisionName = show.flatMap { $0.name.contains("Mini") ? "Mini-Corps" : nil } ?? (idRows[index - 2].isEmpty ? (((show?.name.contains("Class A") ?? false) && !(show?.name.contains("Open Class") ?? false)) ? "Class A" : (show?.name.contains("Open Class") ?? false) ? "Open" : "") : idRows[index - 2])
							let divisionName = (1992...2007).contains(year) && rawDivisionName.hasPrefix("International") ? "International Division" : rawDivisionName
							let rawDivision = divisionName.isEmpty ? nil : divisionName
							let adjustedDivisionName = circuit.abbreviation == "MCA" || (circuit.abbreviation == "DCA" && rawDivision.map { Division.name(for: $0) } == "All-Age Class") ? nil : ((1992...2007).contains(year) && rawDivision.map { Division.name(for: $0) } == "All-Age Class" ? (circuit.abbreviation == "DCM" ? "Senior Division" : "All-Age Division") : ((1992...2007).contains(year) && circuit.abbreviation != "DCA" && rawDivision.map { Division.name(for: $0) } == "Junior Class" ? "Junior Division" : rawDivision))

							if let rank = Int(idRows[index - 1]), let score = Double(idRows[index + 1]) {
								placements[name] = .init(
									rank: rank,
									score: score,
									circuit: circuit,
									division: adjustedDivisionName.map { name in
										EventSpecifiedFields.EventSlotFields.SlotPlacementFields.PlacementDivisionFields(
											name: name,
											circuit: circuit
										)
									}
								)
							}
						}
					}

					// Fold the reconstructed corps records into slotRows as untimed entries so they
					// flow through the same slot assembly below. The fatalError guards trip on
					// malformed records (trailing space / " ,") that would corrupt downstream parsing.
					for record in records {
						if record.contains(" ,") || record.hasSuffix(" ") { print(record); fatalError() }
						if !slotRows.contains(record) {
							slotRows += ["", record]
						}
					}

					for corps in corps {
						let record = await corpsRecord!(corps)
						if record.contains(" ,") || record.hasSuffix(" ") { print(record); fatalError() }
						slotRows += ["", record]
					}
				}

				// Venue comes from the parsed address block: [name, street, city] when present.
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

				// Assemble schedule slots (encore reconstruction + timed/untimed de-duping).
				let slots = slots(from: slotRows, placements: placements)

				// Emit the fully-assembled event.
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
				}
			}

			return .success(events)
		} catch {
			return .failure(.network(error as NSError))
		}
	}

	// Does this scores/recap page belong to the event on `date`? We match against the
	// page's own Yoast meta description ("…results at <Event>, <Month D, YYYY>. View…"),
	// which names only this event — unlike the related-event cards elsewhere on the page.
	// This is the ONLY reliable signal for two-day events, because the solver returns a
	// synthetic 200 for a not-yet-posted recap (a dci.org 404 page), so HTTP status can't
	// distinguish "wrong day" from "not posted".
	static func recap(_ html: String, reports date: Date, using formatStyle: Date.FormatStyle) -> Bool {
		guard let doc = try? HTML(html: html, encoding: .utf8) else { return false }
		let target = date.formatted(formatStyle)
		let descriptions = doc.xpath("//meta[@name='description' or @property='og:description']")
		return descriptions.contains { ($0["content"] ?? "").contains(target) }
	}

	// Placement rows parsed out of a DCI scores page, each normalized to a
	// "<rank> <corps> <score>" string, with a bare division name emitted before that
	// division's rows. Two on-page layouts are handled transparently:
	//   • recap (`.recap-tbl`, one block per division) — current/live loads
	//   • final-scores (`.finalscores`) — historical loads
	// Returns nil when the HTML holds no recognizable table (e.g. a not-found page the
	// solver returned as 200, or scores simply not posted yet).
	static func scoreRows(fromScores html: String) -> [String]? {
		guard let doc = try? HTML(html: html, encoding: .utf8) else { return nil }

		let recapSections = Array(doc.xpath("//div[@class='recap-tbl responsive-tbl']"))
		guard !recapSections.isEmpty else {
			// Final-scores format: a single flat `.finalscores` block of <div> cells.
			return doc
				.xpath("//div[@class='score-tbl responsive-tbl finalscores']")
				.first?
				.xpath("/div")
				.compactMap(\.text)
				.map { $0.replacingOccurrences(of: "[\\r\\n ]+", with: " ", options: .regularExpression) }
				.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
				.filter { $0 != "Place Corps Score" && !$0.contains("Powered") }
		}

		// Recap format: one `.recap-tbl` per division, each preceded by its division
		// heading. Emit the bare division name between sections so downstream code can
		// consume these rows exactly like the final-scores rows above.
		var rows: [String] = []
		for section in recapSections {
			if let division = section.xpath("preceding::h2[1]").first?.text?
				.trimmingCharacters(in: .whitespacesAndNewlines), !division.isEmpty {
				rows.append(division)
			}
			for row in section.xpath("table/tbody/tr") {
				guard
					let corps = row.xpath("td[@class='sticky-td']").first?.text?
					.trimmingCharacters(in: .whitespacesAndNewlines),
					!corps.isEmpty, corps.caseInsensitiveCompare("Corps") != .orderedSame,
					let total = row.xpath("td[last()]").first?.text?
					.replacingOccurrences(of: "[\\r\\n ]+", with: " ", options: .regularExpression)
					.trimmingCharacters(in: .whitespacesAndNewlines)
				else { continue }
				// The last cell is "<score> <rank>" (e.g. "94.700 1"); re-order to
				// "<rank> <corps> <score>" and drop any non-numeric header/total rows.
				let parts = total.components(separatedBy: " ")
				guard parts.count >= 2, Double(parts[0]) != nil, Int(parts[1]) != nil else { continue }
				rows.append("\(parts[1]) \(corps) \(parts[0])")
			}
		}
		return rows
	}

	// Build the event's schedule slots from the flat [time, name, time, name, …] rows,
	// reconstructing encores and dropping duplicate untimed rows for groups that also
	// have a timed appearance. Attaches each slot's placement by performing-group name.
	func slots(
		from slotRows: [String],
		placements: [String: EventSpecifiedFields.EventSlotFields.SlotPlacementFields]
	) -> [EventSpecifiedFields.EventSlotFields] {
		var chunks = slotRows.chunked(into: 2)
		let hasTimes = chunks.allSatisfy { !$0[0].isEmpty }

		// A repeated final group with a time is the winning corps' encore performance;
		// label it so it isn't mistaken for a second competitive appearance.
		if hasTimes {
			let groups = chunks.map { chunk -> String? in
				let record = chunk[1].components(separatedBy: " - ")[0]
				return record.isEmpty || Feature.name(for: record) != nil ? nil : Placement.groupName(for: record)
			}

			if
				let last = groups.lastIndex(where: { $0 != nil }),
				last > 0,
				groups[last] == groups[last - 1] {
				chunks[last][1] = "Encore - " + chunks[last - 1][1]
			}
		}

		// Expand each "Encore - <corps>" marker to carry the corps' full record.
		for index in chunks.indices {
			let components = chunks[index][1].components(separatedBy: " - ")
			guard components.count == 2, components[0] == "Encore" else { continue }
			let corpsName = components[1]
			if let record = chunks.first(where: {
				$0[1].components(separatedBy: " - ").first == corpsName
			})?[1] {
				chunks[index][1] = "Encore - " + record
			}
		}

		// Groups that appear with a time; their untimed duplicates are dropped below.
		let timedGroups: Set<String> = Set(chunks.compactMap { row in
			let time = row[0]
			guard !time.isEmpty else { return nil }
			let record = row[1].components(separatedBy: " - ")[0]
			guard Feature.name(for: record) == nil else { return nil }
			return Placement.groupName(for: record)
		})

		return chunks.compactMap { row -> EventSpecifiedFields.EventSlotFields? in
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

			// Keep only real features and timed performances; drop untimed duplicates.
			if slot.feature == nil && hasTimes && time.isEmpty { return nil }
			if slot.feature == nil && time.isEmpty && timedGroups.contains(groupName) { return nil }

			return slot
		}
	}
}

// MARK: -
// Lineup features that signal an event actually awarded scores; used by the recorded-load
// guard to avoid attaching scores to an event whose schedule never announced them.
private func isPossibleScoreAnnouncement(_ featureName: String) -> Bool {
	[
		"Scores Announced",
		"Awards Ceremony",
		"Retreat"
	].contains(featureName)
}

// MARK: -
private extension Array {
	// Splits into fixed-size groups; the scores/lineup data is a flat [time, name, …] list
	// consumed two elements at a time.
	func chunked(into size: Int) -> [[Element]] {
		return stride(from: 0, to: count, by: size).map {
			Array(self[$0 ..< Swift.min($0 + size, count)])
		}
	}
}
