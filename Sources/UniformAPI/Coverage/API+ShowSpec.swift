// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Show
import struct DrumKitService.IdentifiedShow
import protocol Catena.ResultProviding
import protocol UniformService.ShowSpec

extension API: ShowSpec {
	public func createShow(named name: String) async -> SingleResult<Show.ID> {
		await insert(ShowInput(name: name))
	}
}
