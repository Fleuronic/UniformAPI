// Copyright © Fleuronic LLC. All rights reserved.

import struct Diesel.Feature
import struct Diesel.Corps
import struct DieselService.IdentifiedFeature
import protocol UniformService.FeatureSpec
import protocol Catenary.API

extension API: FeatureSpec {
	public func find(_ feature: Feature, by corps: Corps.Identified?) async -> Self.Result<Feature.Identified> {
		await fetch(where: feature.matches(with: corps)).asyncFlatMap { ids in
			await ids.first.map { id in
				.success(
					feature.identified(
						id: id,
						corps: corps
					)
				)
			}.asyncMapNil {
				let feature = feature.identified(corps: corps)
				return await insert(feature).map { _ in feature }
			}
		}
	}
}
