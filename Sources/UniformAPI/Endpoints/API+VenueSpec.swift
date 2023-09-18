// Copyright © Fleuronic LLC. All rights reserved.

import struct Diesel.Venue
import struct Diesel.Address
import struct Diesel.Location
import struct DieselService.IdentifiedVenue
import protocol UniformService.VenueSpec
import protocol Catenary.API

extension API: VenueSpec {
	public func find(_ venue: Venue, at address: Address.Identified) async -> Self.Result<Venue.Identified> {
		await fetch(where: venue.matches).asyncFlatMap { ids in
			await ids.first.map { id in
				.success(
					venue.identified(
						id: id,
						address: address
					)
				)
			}.asyncMapNil {
				let venue = venue.identified(address: address)
				return await insert(venue).map { _ in venue }
			}
		}
	}
}
