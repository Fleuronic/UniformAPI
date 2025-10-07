// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Division
import struct DrumKit.Circuit
import struct DrumKitService.IdentifiedDivision
import protocol Catena.ResultProviding
import protocol UniformService.DivisionSpec

extension API: DivisionSpec {
	public func createDivision(named name: String, inCircuitWith circuitID: Circuit.ID) async -> SingleResult<Division.ID> {
		await insert(
			DivisionInput(
				name: name, 
				circuitID: circuitID
			)
		)
	}
}
