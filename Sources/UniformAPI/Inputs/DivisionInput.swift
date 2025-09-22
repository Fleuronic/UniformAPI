import PersistDB
import struct DrumKit.Division
import protocol Caesura.Input

struct DivisionInput {
	let name: String
}

extension DivisionInput: Input {
	typealias ID = Division.ID

	var valueSet: ValueSet<Division.Identified> {
		[\.value.name == name]
	}
}
