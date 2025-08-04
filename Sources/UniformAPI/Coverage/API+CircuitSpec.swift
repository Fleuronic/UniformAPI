// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Circuit
import struct DrumKitService.IdentifiedCircuit
import protocol Catena.ResultProviding
import protocol UniformService.CircuitSpec

extension API: CircuitSpec {
	public func createCircuit(abbreviatedAs abbreviation: String) async -> SingleResult<Circuit.ID> {
		await insert(CircuitInput(abbreviation: abbreviation))
	}
}
