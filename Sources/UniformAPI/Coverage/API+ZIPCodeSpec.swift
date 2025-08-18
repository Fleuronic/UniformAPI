// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.ZIPCode
import struct DrumKitService.IdentifiedZIPCode
import protocol Catena.ResultProviding
import protocol UniformService.ZIPCodeSpec

extension API: ZIPCodeSpec {
	public func createZIPCode(with code: String) async -> SingleResult<ZIPCode.ID> {
		await insert(ZIPCodeInput(code: code))
	}
}
