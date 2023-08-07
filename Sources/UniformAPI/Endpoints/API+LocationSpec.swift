// Copyright © Fleuronic LLC. All rights reserved.

import struct Diesel.Location
import struct DieselService.IdentifiedLocation
import protocol UniformService.LocationSpec
import protocol Catenary.API

extension API: LocationSpec {
    public func find(_ location: Location) async -> Self.Result<Location.Identified> {
		await fetch(where: location.matches).asyncFlatMap { ids in
			await ids.first.map(location.identified).map(Result.success).asyncMapNil {
				let location = location.identified()
				return await insert(location).map { _ in location }
            }
		}
	}
}
