import PersistDB
import struct DrumKit.Show
import protocol Caesura.Input

struct ShowInput {
	let name: String
}

extension ShowInput: Input {
	typealias ID = Show.ID

	var valueSet: ValueSet<Show.Identified> {
		[\.value.name == name]
	}
}
