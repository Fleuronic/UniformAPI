// Copyright © Fleuronic LLC. All rights reserved.

import struct DrumKit.Slot
import struct DrumKit.Event
import struct DrumKit.Time
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

	public func updateSlot(with id: Slot.ID, to time: Time) async -> SingleResult<Slot.ID> {
		await update(SlotInput(time: time), with: id)
	}

	public func deleteSlots(with ids: [Slot.ID]) async -> Results<Slot.ID> {
		await delete(Slot.Identified.self, with: ids)
	}
}
