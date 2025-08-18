import PersistDB
import struct DrumKit.Venue
import struct DrumKit.Address
import protocol Caesura.Input

struct VenueInput {
	let name: String
	let host: String?
	let addressID: Address.ID
}

extension VenueInput: Input {
	typealias ID = Venue.ID

	var valueSet: ValueSet<Venue.Identified> {
		var valueSet: ValueSet<Venue.Identified> = [
			\.value.name == name,
			\.address == addressID
		]

		host.map { valueSet = valueSet.update(with: [\.value.host == $0]) }

		return valueSet
	}
}
