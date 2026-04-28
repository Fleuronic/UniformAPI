import PersistDB
import struct DrumKit.Performance
import struct DrumKit.Corps
import struct DrumKit.Ensemble
import struct DrumKit.Placement
import protocol Caesura.Input

struct PerformanceInput {
	let corpsID: Corps.ID?
	let ensembleID: Ensemble.ID?
	let placementID: Placement.ID?

	// TODO
	init(
		corpsID: Corps.ID? = nil,
		ensembleID: Ensemble.ID? = nil,
		placementID: Placement.ID?
	) {
		self.corpsID = corpsID
		self.ensembleID = ensembleID
		self.placementID = placementID
	}
}

extension PerformanceInput: Input {
	typealias ID = Performance.ID

	var valueSet: ValueSet<Performance.Identified> {
		var valueSet: ValueSet<Performance.Identified> = []

		corpsID.map { valueSet = valueSet.update(with: [\.corps == $0]) }
		ensembleID.map { valueSet = valueSet.update(with: [\.ensemble == $0]) }
		placementID.map { valueSet = valueSet.update(with: [\.placement == $0]) }

		return valueSet
	}
}
