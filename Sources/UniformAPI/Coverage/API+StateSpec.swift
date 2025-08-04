// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.State
import struct DrumKit.Country
import struct DrumKitService.IdentifiedState
import protocol Catena.ResultProviding
import protocol UniformService.StateSpec

extension API: StateSpec {
	public func createState(abbreviatedAs abbreviation: String, inCountryWith countryID: Country.ID) async -> SingleResult<State.ID> {
		await insert(
			StateInput(
				abbreviation: abbreviation,
				countryID: countryID
			)
		)
	}
}
