// Copyright © Fleuronic LLC. All rights reserved.

import struct Diesel.Corps
import struct Diesel.Feature
import struct Uniform.Schedule

extension Schedule: Decodable {
	public init(from decoder: Decoder) throws {
		let corps: Corps?
		let feature: Feature?
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let unitName = try container.decode(String.self, forKey: .unitName)
			.replacingOccurrences(of: "  ", with: " ")
			.replacingOccurrences(of: "[:-] ", with: "– ", options: .regularExpression)
			.replacingOccurrences(of: "([a-z])– ", with: "$1 – ", options: .regularExpression)
			.normalized(from: .corps)
			.normalized(from: .features)
		let displayCity = try container.decodeIfPresent(String.self, forKey: .displayCity)
		let timeString = try container.decodeIfPresent(String.self, forKey: .time)
	
		let featureNames: [String] = .init(resource: .features)
		if let featureName = unitName.deleted(from: .corps) {
			let components = featureName.components(separatedBy: " – ")
			let name = components.count > 1 ? components[0].normalized(from: .features) + " – " + components[1] : featureName
		
			feature = .init(name: name)
			corps = nil
		} else if featureNames.contains(where: unitName.contains) {
			let components = unitName.components(separatedBy: " – ")
			var featureName = components[0].normalized(from: .features)
			var corpsName = components.count > 1 ? components[1].normalized(from: .corps) : nil
		
			if featureName.deleted(from: .features) != nil {
				(featureName, corpsName) = (corpsName!, nil)
			} else if let name = corpsName, featureNames.contains(where: name.contains) {
				(featureName, corpsName) = (name, featureName)
			}
		
			feature = .init(name: featureName)
			corps = corpsName.map(Corps.init)
		} else {
			feature = nil
			corps = .init(name: unitName.normalized(from: .corps))
		}
		
		self.init(
			feature: feature,
			corps: corps,
			displayCity: corps.flatMap {
				.inserted(for: $0.name, from: .locations) ?? displayCity?.normalized(from: .locations)
			},
			time: timeString.map {
				let components: [String]
				if $0.contains(" - ") {
					components = $0.components(separatedBy: " - ")
				} else if $0.contains(".  ") {
					components = $0.components(separatedBy: ".  ")
				} else if $0.contains(") ") {
					components = $0.components(separatedBy: ") ")
				} else {
					components = []
				}
				
				if components.isEmpty {
					return $0.contains("M") ? $0 : "\($0) PM"
				} else {
					let index = Int(components[0])!
					let time = components[1]
					let hour = Int(time.components(separatedBy: ":")[0].replacingOccurrences(of: " ", with: ""))!
					let amPM = (hour < 12) && index <= 12 ? "AM" : "PM"
					return time.contains(" ") ? time : "\(time) \(amPM)"
				}
			}
		)
	}
}

// MARK -
private extension Schedule {
	enum CodingKeys: CodingKey {
		case unitName
		case displayCity
		case time
	}
}