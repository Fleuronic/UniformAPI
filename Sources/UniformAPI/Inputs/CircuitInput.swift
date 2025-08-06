import Uniform
import PersistDB
import struct DrumKit.Circuit
import protocol Caesura.Input

struct CircuitInput {
	let name: String
	let abbreviation: String
}

// MARK: -
extension CircuitInput {
	init(abbreviation: String) {
		name = Circuit.name(for: abbreviation)

		self.abbreviation = abbreviation
	}
}

// MARK: -
extension CircuitInput: Input {
	typealias ID = Circuit.ID

	var valueSet: ValueSet<Circuit.Identified> {
		[
			\.value.name == name,
			\.value.abbreviation == abbreviation
		]
	}
}
