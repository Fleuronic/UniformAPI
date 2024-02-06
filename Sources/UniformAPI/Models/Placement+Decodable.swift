// Copyright © Fleuronic LLC. All rights reserved.

import struct Uniform.Placement

extension Placement: Decodable {
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			rank: try container.decode(Int.self, forKey: .rank),
			groupName: try container.decode(String.self, forKey: .groupName),
			totalScore: try container.decode(Double.self, forKey: .totalScore),
			divisionName: try container.decode(String.self, forKey: .divisionName)
		)
	}
}

// MARK -
private extension Placement {
	enum CodingKeys: CodingKey {
		case rank
		case groupName
		case totalScore
		case divisionName	
	}
}