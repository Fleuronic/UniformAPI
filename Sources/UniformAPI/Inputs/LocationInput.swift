import PersistDB
import struct DrumKit.Location
import struct DrumKit.State
import protocol Caesura.Input

struct LocationInput {
	let city: String?
	let stateID: State.ID
}

extension LocationInput: Input {
	typealias ID = Location.ID

	var valueSet: ValueSet<Location.Identified> {
		var valueSet: ValueSet<Location.Identified> = [\.state == stateID]
		city.map { valueSet = valueSet.update(with: [\.value.city == $0]) }

		return valueSet
	}
}
