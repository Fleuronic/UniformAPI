// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Circuit
import struct DrumKitService.IdentifiedCircuit
import protocol Catena.ResultProviding
import protocol UniformService.CircuitSpec

extension API: CircuitSpec {
	public func createCircuit(named name: String, abbreviatedAs abbreviation: String?) async -> SingleResult<Circuit.ID> {
		await insert(
			CircuitInput(
				name: name,
				abbreviation: abbreviation
			)
		)
	}
}
