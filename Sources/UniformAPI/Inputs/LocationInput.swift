import PersistDB
import struct DrumKit.Location
import struct DrumKit.State
import protocol Caesura.Input

struct LocationInput {
	let city: String
	let stateID: State.ID
}

extension LocationInput: Input {
	typealias ID = Location.ID

	var valueSet: ValueSet<Location.Identified> {
		[
			\.value.city == city,
			\.state == stateID
		]
	}
}
