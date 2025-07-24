// Copyright © Fleuronic LLC. All rights reserved.

import struct Uniform.Corps
import protocol Catena.ResultProviding
import protocol UniformService.CorpsFields

public struct API<
	CorpsSpecifiedFields: CorpsFields
>: @unchecked Sendable {}

// MARK: -
public extension API {
	func specifyingCorpsFields<Fields>(_: Fields.Type) -> API<
		Fields
	> {
		.init()
	}
}

public extension API<
	Corps.IDFields
> {
	init() {}
}

// MARK: -
extension API: ResultProviding {
	public typealias Error = Swift.Error
}
