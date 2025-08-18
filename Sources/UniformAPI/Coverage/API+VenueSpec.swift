// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Venue
import struct DrumKit.Address
import struct DrumKitService.IdentifiedVenue
import protocol Catena.ResultProviding
import protocol UniformService.VenueSpec

extension API: VenueSpec {
	public func createVenue(named name: String, hostedBy host: String?, atAddressWith addressID: Address.ID) async -> SingleResult<Venue.ID> {
		await insert(
			VenueInput(
				name: name,
				host: host,
				addressID: addressID
			)
		)
	}
}
