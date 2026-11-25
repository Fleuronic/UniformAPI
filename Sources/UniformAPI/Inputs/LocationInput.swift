import PersistDB
import struct DrumKit.Location
import struct DrumKit.State
import struct DrumKit.Country
import protocol Caesura.Input

struct LocationInput {
	let city: String?
	let stateID: State.ID?
	let countryID: Country.ID
}

extension LocationInput: Input {
	typealias ID = Location.ID

	var valueSet: ValueSet<Location.Identified> {
		var valueSet: ValueSet<Location.Identified> = [\.country == countryID]
		city.map { valueSet = valueSet.update(with: [\.value.city == $0]) }
		stateID.map { valueSet = valueSet.update(with: [\.state == $0]) }

		return valueSet
	}
}
