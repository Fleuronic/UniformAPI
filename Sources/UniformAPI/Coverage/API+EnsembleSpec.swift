// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Ensemble
import struct DrumKit.Location
import struct DrumKitService.IdentifiedEnsemble
import protocol Catena.ResultProviding
import protocol UniformService.EnsembleSpec

extension API: EnsembleSpec {
	public func createEnsemble(named name: String, basedInLocationWith locationID: Location.ID?) async -> SingleResult<Ensemble.ID> {
		await insert(
			EnsembleInput(
				name: name,
				locationID: locationID
			)
		)
	}
}
