import PersistDB
import struct DrumKit.State
import struct DrumKit.Country
import protocol Caesura.Input

struct StateInput {
	let abbreviation: String
	let countryID: Country.ID
}

extension StateInput: Input {
	typealias ID = State.ID

	var valueSet: ValueSet<State.Identified> {
		[
			\.value.abbreviation == abbreviation,
			\.country == countryID
		]
	}
}
