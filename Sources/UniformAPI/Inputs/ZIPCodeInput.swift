import PersistDB
import struct DrumKit.ZIPCode
import protocol Caesura.Input

struct ZIPCodeInput {
	let code: String
}

extension ZIPCodeInput: Input {
	typealias ID = ZIPCode.ID

	var valueSet: ValueSet<ZIPCode.Identified> {
		[\.value.code == code]
	}
}
