// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Performance
import struct DrumKit.Corps
import struct DrumKit.Ensemble
import struct DrumKit.Placement
import struct DrumKitService.IdentifiedPerformance
import protocol Catena.ResultProviding
import protocol UniformService.PerformanceSpec

extension API: PerformanceSpec {
	public func createPerformance(byCorpsWith corpsID: Corps.ID?, ensembleWith ensembleID: Ensemble.ID?, toPlacementWith placementID: Placement.ID?) async -> SingleResult<Performance.ID> {
		await insert(
			PerformanceInput(
				corpsID: corpsID,
				ensembleID: ensembleID,
				placementID: placementID
			)
		)
	}

	public func updatePerformance(with id: Performance.ID, toPlacementWith placementID: Placement.ID) async -> SingleResult<Performance.ID> {
		await update(PerformanceInput(placementID: placementID), with: id)
	}

	public func deletePerformances(with ids: [Performance.ID]) async -> Results<Performance.ID> {
		await delete(Performance.Identified.self, with: ids)
	}
}
