// Copyright © Fleuronic LLC. All rights reserved.

import enum Uniform.Span
import struct Uniform.Event
import struct Uniform.Placement
import struct Uniform.Site
import struct UniformService.Service
import struct Foundation.Data
import protocol Catenary.API
import protocol UniformService.PlacementSpec

extension API: PlacementSpec {
	public func eventPlacementData(
		year: Int,
		eventData: Data,
		slugsResult: Self.Result<[String]>
	) async -> Self.Result<Service.EventPlacementData> {
		await slugsResult.asyncMap { slugs in
			let events = try! decoder.decode([Event].self, from: eventData)
			return await zip(
				events.sorted { $0.slug < $1.slug },
				slugs.asyncMap { slug in
					await placements(
						slug: slug,
						year: year
					)
				}
			).map { (event: $0.0, placements: $0.1) }
		}.map(Array.init)
	}

	public func eventPlacementData(
		year: Int,
		span: Span,
		slugsResult: Self.Result<[String]>
	) async -> Self.Result<Service.EventPlacementData> {
		await slugsResult.asyncMap { slugs in
			await slugs.asyncCompactMap { slug in
				let site = await Site(
					domain: .dci,
					path: .events,
					slug: slug,
					year: year
				)
			
				return await site?.data.asyncMap { eventData in
					let event = try? decoder.decode(Event.self, from: eventData)
					let placements = (span == .upcoming || year == 2021) ? [] : await placements(
						slug: slug,
						year: year,
						data: year <= 2017 ? site?.data(at: .scores) : nil
					)
				
					return await event.asyncMap { ($0, placements) }
				}
			}.compactMap { $0 }
		}
	}
}

// MARK: -
private extension API {
	func placements(
		slug: String,
		year: Int,
		data: Data? = nil
	) async -> [Placement] {
		if let data {
			try! decoder.decode([Placement].self, from: data)
		} else {
			await Site(
				domain: .dci,
				path: .scores,
				slug: slug.normalized(from: .events),
				year: year
			)?.data.flatMap { data in
				try! decoder.decode([Placement].self, from: data)
			} ?? []
		}
	}
}
