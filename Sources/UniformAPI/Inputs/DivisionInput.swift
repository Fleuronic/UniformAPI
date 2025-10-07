import PersistDB
import struct DrumKit.Division
import struct DrumKit.Circuit
import protocol Caesura.Input

struct DivisionInput {
	let name: String
	let circuitID: Circuit.ID
}

extension DivisionInput: Input {
	typealias ID = Division.ID

	var valueSet: ValueSet<Division.Identified> {
		[
			\.value.name == name,
			\.circuit == circuitID
		]
	}
}
