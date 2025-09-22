// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Placement
import struct DrumKit.Division
import struct DrumKitService.IdentifiedPlacement
import protocol Catena.ResultProviding
import protocol UniformService.PlacementSpec

extension API: PlacementSpec {
	public func createPlacement(at rank: Int, with score: Double, inDivisionWith divisionID: Division.ID?) async -> SingleResult<Placement.ID> {
		await insert(
			PlacementInput(
				rank: rank,
				score: score,
				divisionID: divisionID
			)
		)
	}
}
