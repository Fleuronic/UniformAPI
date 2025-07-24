// Copyright © Fleuronic LLC. All rights reserved.

import struct Uniform.Corps
import protocol Catena.ResultProviding
import protocol Catenoid.Fields
import protocol UniformService.CorpsSpec

extension API: CorpsSpec {
	public func listCorps() async -> Results<CorpsSpecifiedFields> {
		.success([])
	}
}
