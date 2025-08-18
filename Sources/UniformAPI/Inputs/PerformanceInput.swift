import PersistDB
import struct DrumKit.Performance
import struct DrumKit.Corps
import struct DrumKit.Ensemble
import protocol Caesura.Input

struct PerformanceInput {
	let corpsID: Corps.ID?
	let ensembleID: Ensemble.ID?
}

extension PerformanceInput: Input {
	typealias ID = Performance.ID

	var valueSet: ValueSet<Performance.Identified> {
		var valueSet: ValueSet<Performance.Identified> = []

		corpsID.map { valueSet = valueSet.update(with: [\.corps == $0]) }
		ensembleID.map { valueSet = valueSet.update(with: [\.ensemble == $0]) }

		return valueSet
	}
}
