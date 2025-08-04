import PersistDB
import Foundation
import struct DrumKit.Event
import struct DrumKit.Location
import struct DrumKit.Circuit
import struct DrumKit.Show
import protocol Caesura.Input

struct EventInput {
	let date: Date
	let locationID: Location.ID
	let circuitID: Circuit.ID?
	let showID: Show.ID?
}

extension EventInput: Input {
	typealias ID = Event.ID

	var valueSet: ValueSet<Event.Identified> {
		var valueSet: ValueSet<Event.Identified> = [
			\.value.date == date,
			\.location == locationID
		]

		circuitID.map { valueSet = valueSet.update(with: [\.circuit == $0]) }
		showID.map { valueSet = valueSet.update(with: [\.show == $0]) }

		return valueSet
	}
}
