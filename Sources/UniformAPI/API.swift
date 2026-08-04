// Copyright © Fleuronic LLC. All rights reserved.

import Papyrus
import Schemata
import DrumKit
import enum Catenary.Request
import struct Uniform.Event
import struct Uniform.Corps
import struct Catenary.Schema
import struct Caesura.EndpointAPI
import protocol UniformService.EventFields
import protocol UniformService.CorpsFields
import protocol Catena.ResultProviding
import protocol Catenary.Schematic
import protocol Caesura.Endpoint
import protocol Caesura.API

public struct API<
	Endpoint: Caesura.Endpoint,
	EventSpecifiedFields: EventFields,
	CorpsSpecifiedFields: CorpsFields
>: @unchecked Sendable {
	public let endpoint: Endpoint
}

// MARK: -
public extension API {
	func specifyingEventFields<Fields>(_: Fields.Type) -> API<
		Endpoint,
		Fields,
		CorpsSpecifiedFields
	> {
		.init(endpoint: endpoint)
	}

	func specifyingCorpsFields<Fields>(_: Fields.Type) -> API<
		Endpoint,
		EventSpecifiedFields,
		Fields
	> {
		.init(endpoint: endpoint)
	}
}

public extension API where Endpoint == EndpointAPI {
	init(apiKey: String) {
		let url = "https://diesel.hasura.app/v1/graphql"
		let provider = Provider(baseURL: url).modifyRequests { request in
			request.addHeader("x-hasura-admin-secret", value: apiKey)
		}

		self.init(endpoint: .init(provider: provider))
	}
}

// MARK: -
extension API: Caesura.API {
	// MARK: API
	public typealias APIError = Request.Error

	// MARK: Storage
	public typealias StorageError = Self.Error
}

extension API: Schematic {
	// MARK: Schematic
	public static var schema: Schema {
		.init(
			DrumKit.Event.Identified.self,
			Location.Identified.self,
			State.Identified.self,
			Country.Identified.self,
			Circuit.Identified.self,
			Show.Identified.self,
			Venue.Identified.self,
			Address.Identified.self,
			ZIPCode.Identified.self,
			Slot.Identified.self,
			Feature.Identified.self,
			DrumKit.Corps.Identified.self,
			Ensemble.Identified.self,
			Performance.Identified.self,
			Placement.Identified.self,
			Division.Identified.self
		)
	}
}
