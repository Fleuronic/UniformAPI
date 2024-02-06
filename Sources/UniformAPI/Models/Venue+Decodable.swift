// Copyright © Fleuronic LLC. All rights reserved.

import struct Uniform.Venue

extension Venue: Decodable {
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			name: try container.decode(String.self, forKey: .name)
		)
	}
}

// MARK -
private extension Venue {
	enum CodingKeys: CodingKey {
		case name
	}
}