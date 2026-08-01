import Uniform
import PersistDB
import struct DrumKit.Circuit
import protocol Caesura.Input

struct CircuitInput {
	let name: String
	let abbreviation: String?
}

// MARK: -
extension CircuitInput: Input {
	typealias ID = Circuit.ID

	var valueSet: ValueSet<Circuit.Identified> {
		var valueSet: ValueSet<Circuit.Identified> = [\.value.name == name]

		abbreviation.map { valueSet = valueSet.update(with: [\.value.abbreviation == $0]) }

		return valueSet
	}
}
