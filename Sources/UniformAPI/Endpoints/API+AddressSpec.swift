// Copyright © Fleuronic LLC. All rights reserved.

import struct Diesel.Address
import struct Diesel.Location
import struct DieselService.IdentifiedAddress
import protocol UniformService.AddressSpec
import protocol Catenary.API

extension API: AddressSpec {
	public func find(_ address: Address, in location: Location.Identified) async -> Self.Result<Address.Identified> {
		await fetch(where: address.matches).asyncFlatMap { ids in
			await ids.first.map { id in
				.success(
					address.identified(
						id: id,
						location: location
					)
				)
			}.asyncMapNil {
				let address = address.identified(location: location)
				return await insert(address).map { _ in address }
			}
		}
	}
}
