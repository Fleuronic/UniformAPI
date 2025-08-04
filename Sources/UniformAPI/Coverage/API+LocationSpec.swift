// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Location
import struct DrumKit.State
import struct DrumKitService.IdentifiedLocation
import protocol Catena.ResultProviding
import protocol UniformService.LocationSpec

extension API: LocationSpec {
	public func createLocation(basedIn city: String, inStateWith stateID: State.ID) async -> SingleResult<Location.ID> {
		await insert(
			LocationInput(
				city: city,
				stateID: stateID
			)
		)
	}
}
