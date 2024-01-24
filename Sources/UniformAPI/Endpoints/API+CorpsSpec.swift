// Copyright © Fleuronic LLC. All rights reserved.

import struct Diesel.Corps
import struct Diesel.Location
import struct DieselService.IdentifiedCorps
import struct DieselService.CorpsNameLocationFields
import protocol UniformService.CorpsSpec
import protocol Catenary.API

extension API: CorpsSpec {
	public func find(_ corps: Corps, from location: Location.Identified?) async -> Self.Result<Corps.Identified> {
		if let location {
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
		} else {
			await fetch(CorpsNameLocationFields.self, where: corps.matches).asyncFlatMap { fields in
				await fields.first.map { fields in
					.success(.init(fields: fields))
				}.asyncMapNil {
					let components = String.inserted(for: corps.name, from: .locations)!.components(separatedBy: ", ")
					let location = Location(city: components[0], state: components[1])
					return await find(location).asyncFlatMap { location in
						let corps = corps.identified(location: location)
						return await insert(corps).map { _ in corps }
					}
				}
			}
		}
	}
}
