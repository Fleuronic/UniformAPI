import PersistDB
import struct DrumKit.Circuit
import protocol Caesura.Input

struct CircuitInput {
	let name: String
	let abbreviation: String
}

// MARK: -
extension CircuitInput {
	init(abbreviation: String) {
		self.abbreviation = abbreviation

		switch abbreviation {
		case "DCI":
			name = "Drum Corps International"
		case "DCA":
			name = "Drum Corps Associates"
		case "DCM":
			name = "Drum Corps Midwest"
		case "DCH":
			name = "Drum Corps Holland"
		case "AL":
			name = "American Legion"
		case "VFW":
			name = "Veterans of Foreign Wars"
		case "CAMQ":
			name = "Circuit des associations musicales du Québec"
		case "FAMQ":
			name = "Fédération des Associations Musicales du Québec"
		default:
			fatalError()
		}
	}
}

// MARK: -
extension CircuitInput: Input {
	typealias ID = Circuit.ID

	var valueSet: ValueSet<Circuit.Identified> {
		[
			\.value.name == name,
			\.value.abbreviation == abbreviation
		]
	}
}
