// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Country
import struct DrumKitService.IdentifiedCountry
import protocol Catena.ResultProviding
import protocol UniformService.CountrySpec

extension API: CountrySpec {
	public func createCountry(named name: String) async -> SingleResult<Country.ID> {
		await insert(CountryInput(name: name))
	}
}
