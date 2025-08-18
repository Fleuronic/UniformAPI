// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Address
import struct DrumKit.Location
import struct DrumKit.ZIPCode
import struct DrumKitService.IdentifiedAddress
import protocol Catena.ResultProviding
import protocol UniformService.AddressSpec

extension API: AddressSpec {
	public func createAddress(at streetAddress: String, inLocationWith locationID: Location.ID, inZIPCodeWith zipCodeID: ZIPCode.ID) async -> SingleResult<Address.ID> {
		await insert(
			AddressInput(
				streetAddress: streetAddress,
				locationID: locationID,
				zipCodeID: zipCodeID
			)
		)
	}
}
