import PersistDB
import struct DrumKit.Placement
import struct DrumKit.Division
import protocol Caesura.Input

struct PlacementInput {
	let rank: Int
	let score: Double
	let divisionID: Division.ID?
}

extension PlacementInput: Input {
	typealias ID = Placement.ID

	var valueSet: ValueSet<Placement.Identified> {
		var valueSet: ValueSet<Placement.Identified> = [
			\.value.rank == rank,
			\.value.score == score
		]

		divisionID.map { valueSet = valueSet.update(with: [\.division == $0]) }

		return valueSet
	}
}
