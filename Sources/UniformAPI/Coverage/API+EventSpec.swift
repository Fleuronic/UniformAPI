// Copyright © Fleuronic LLC. All rights reserved.

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

extension API: EventSpec {
	public func listEvents(with urls: [URL]) async -> Results<EventSpecifiedFields> {
		guard !urls.isEmpty else { return .success([]) }

		let currentYear = Calendar.current.component(.year, from: .init())
		return await listEvents(for: currentYear, with: urls)
	}

	public func listEvents(for year: Int, with corpsRecord: ((String) async -> String)?) async -> Results<EventSpecifiedFields> {
		await listEvents(for: year, excluding: [], with: corpsRecord)
	}

	public func listEvents(for year: Int, excluding excludedURLs: Set<URL>, excludingScoresFor scoresExcludedURLs: Set<URL> = [], with corpsRecord: ((String) async -> String)?) async -> Results<EventSpecifiedFields> {
		let urls = (try? await eventURLs(for: year)) ?? []

		if year >= 2024, urls.isEmpty { return .success([]) }

		return await listEvents(for: year, with: urls.isEmpty ? nil : urls, excluding: excludedURLs, excludingScoresFor: scoresExcludedURLs, with: corpsRecord)
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
