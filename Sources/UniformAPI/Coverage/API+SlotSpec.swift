// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Slot
import struct DrumKit.Event
import struct DrumKitService.IdentifiedSlot
import protocol Catena.ResultProviding
import protocol UniformService.SlotSpec

extension API: SlotSpec {
	public func createSlots(with parameters: [Slot.CreationParameters], inEventWith eventID: Event.ID) async -> Results<Slot.ID> {
		await insert(
			parameters.map { 
				SlotInput(
					time: $0.time,
					eventID: eventID,
					performanceID: $0.performanceID,
					featureID: $0.featureID
				) 
			}
		)
	}
}
