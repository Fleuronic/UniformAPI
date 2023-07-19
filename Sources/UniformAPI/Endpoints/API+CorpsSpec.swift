// Copyright © Fleuronic LLC. All rights reserved.

import struct Diesel.Corps
import struct Diesel.Location
import struct DieselService.IdentifiedCorps
import protocol UniformService.CorpsSpec
import protocol Catenary.API

extension API: CorpsSpec {
	public func find(_ corps: Corps, from location: Location.Identified) async -> Self.Result<Corps.Identified> {
		await fetch(where: corps.matches(with: location)).asyncFlatMap { ids in
			await ids.first.map { id in
				.success(
					corps.identified(
						id: id,
						location: location
					)
				)
			}.asyncMapNil {
				let corps = corps.identified(location: location)
				return await insert(corps).map { _ in corps }
			}
		}
	}
}
