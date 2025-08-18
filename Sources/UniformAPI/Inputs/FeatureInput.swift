import PersistDB
import struct DrumKit.Feature
import protocol Caesura.Input

struct FeatureInput {
	let name: String
}

extension FeatureInput: Input {
	typealias ID = Feature.ID

	var valueSet: ValueSet<Feature.Identified> {
		[\.value.name == name]
	}
}
