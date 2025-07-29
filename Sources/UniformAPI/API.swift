// Copyright © Fleuronic LLC. All rights reserved.

import struct Uniform.Event
import struct Uniform.Corps
import protocol Catena.ResultProviding
import protocol UniformService.EventFields
import protocol UniformService.CorpsFields

public struct API<
	EventSpecifiedFields: EventFields,
	CorpsSpecifiedFields: CorpsFields
>: @unchecked Sendable {}

// MARK: -
public extension API {
	func specifyingEventFields<Fields>(_: Fields.Type) -> API<
		Fields,
		CorpsSpecifiedFields
	> {
		.init()
	}

	func specifyingCorpsFields<Fields>(_: Fields.Type) -> API<
		EventSpecifiedFields,
		Fields
	> {
		.init()
	}
}

public extension API<
	Event.IDFields,
	Corps.IDFields
> {
	init() {}
}

// MARK: -
extension API: ResultProviding {
	public typealias Error = Swift.Error
}
