import PersistDB
import struct DrumKit.Country
import protocol Caesura.Input

struct CountryInput {
	let name: String
}

extension CountryInput: Input {
	typealias ID = Country.ID

	var valueSet: ValueSet<Country.Identified> {
		[\.value.name == name]
	}
}
