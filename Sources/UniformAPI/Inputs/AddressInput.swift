import PersistDB
import struct DrumKit.Address
import struct DrumKit.Location
import struct DrumKit.ZIPCode
import protocol Caesura.Input

struct AddressInput {
	let streetAddress: String
	let locationID: Location.ID
	let zipCodeID: ZIPCode.ID
}

extension AddressInput: Input {
	typealias ID = Address.ID

	var valueSet: ValueSet<Address.Identified> {
		[
			\.value.streetAddress == streetAddress,
			\.location == locationID,
			\.zipCode == zipCodeID
		]
	}
}
