// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Division
import struct DrumKitService.IdentifiedDivision
import protocol Catena.ResultProviding
import protocol UniformService.DivisionSpec

extension API: DivisionSpec {
	public func createDivision(named name: String) async -> SingleResult<Division.ID> {
		await insert(DivisionInput(name: name))
	}
}
