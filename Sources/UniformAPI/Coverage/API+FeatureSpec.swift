// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Feature
import struct DrumKitService.IdentifiedFeature
import protocol Catena.ResultProviding
import protocol UniformService.FeatureSpec

extension API: FeatureSpec {
	public func createFeature(named name: String) async -> SingleResult<Feature.ID> {
		await insert(FeatureInput(name: name))
	}
}
