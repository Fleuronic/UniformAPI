// Copyright © Fleuronic LLC. All rights reserved.

import struct Uniform.Corps
import protocol Catena.ResultProviding
import protocol UniformService.CorpsFields

public struct API<
	CorpsSpecifiedFields: CorpsFields
>: @unchecked Sendable {}

public extension API<
	Corps.IDFields
> {
	init() {}
}

extension API: ResultProviding {
	public typealias Error = Swift.Error
}
