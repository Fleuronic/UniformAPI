import PersistDB
import struct DrumKit.Slot
import struct DrumKit.Time
import struct DrumKit.Event
import struct DrumKit.Performance
import struct DrumKit.Feature
import protocol Caesura.Input

struct SlotInput {
	let time: Time?
	let eventID: Event.ID
	let performanceID: Performance.ID?
	let featureID: Feature.ID?
}

extension SlotInput: Input {
	typealias ID = Slot.ID

	var valueSet: ValueSet<Slot.Identified> {
		var valueSet: ValueSet<Slot.Identified> = [\.event == eventID]

		time.map { valueSet = valueSet.update(with: [\.value.time == $0]) }
		performanceID.map { valueSet = valueSet.update(with: [\.performance == $0]) }
		featureID.map { valueSet = valueSet.update(with: [\.feature == $0]) }

		return valueSet
	}
}
