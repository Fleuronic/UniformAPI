// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Location
import struct DrumKit.State
import struct DrumKit.Country
import struct DrumKitService.IdentifiedLocation
import protocol Catena.ResultProviding
import protocol UniformService.LocationSpec

extension API: LocationSpec {
	public func createLocation(in city: String?, inStateWith stateID: State.ID?, inCountryWith countryID: Country.ID) async -> SingleResult<Location.ID> {
		await insert(
			LocationInput(
				city: city,
				stateID: stateID,
				countryID: countryID
			)
		)
	}
}
