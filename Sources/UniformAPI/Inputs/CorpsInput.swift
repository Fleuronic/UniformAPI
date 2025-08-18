import PersistDB
import struct DrumKit.Corps
import struct DrumKit.Location
import protocol Caesura.Input

struct CorpsInput {
	let name: String
	let locationID: Location.ID
}

extension CorpsInput: Input {
	typealias ID = Corps.ID

	var valueSet: ValueSet<Corps.Identified> {
		[
			\.value.name == name,
			\.location == locationID
		]
	}
}
