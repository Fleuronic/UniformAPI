import PersistDB
import struct DrumKit.Ensemble
import struct DrumKit.Location
import protocol Caesura.Input

struct EnsembleInput {
	let name: String
	let locationID: Location.ID?
}

extension EnsembleInput: Input {
	typealias ID = Ensemble.ID

	var valueSet: ValueSet<Ensemble.Identified> {
		var valueSet: ValueSet<Ensemble.Identified> = [\.value.name == name]

		locationID.map { valueSet = valueSet.update(with: [\.location == $0]) }
		
		return valueSet
	}
}
