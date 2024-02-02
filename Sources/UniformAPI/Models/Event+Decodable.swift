import struct Uniform.Event
import struct Uniform.Venue
import struct Uniform.Schedule

extension Event: Decodable {
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let name: String
		let slug: String
		let startDate: String
		let startTime: String?
		let venueHost: String?
		let venueState: String
		let venueZIP: String?
		let schedules: [Schedule]?
		let timeZone = try? container.decode(String.self, forKey: .timeZone)

		var venueName: String?
		var venueAddress: String?
		var venueCity: String

		if timeZone == nil {
			let date = try container.decode(String.self, forKey: .date)
			let location = try container.decode(String.self, forKey: .location).normalized(from: .locations)
			let dateComponents = date.components(separatedBy: "T")
			let locationComponents = location.components(separatedBy: ", ")

			name = try container.decode(String.self, forKey: .eventName).normalized(from: .shows)
			slug = try container.decode(String.self, forKey: .slug)
			startDate = dateComponents[0]
			startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
			venueAddress = nil
			venueZIP = nil
			venueCity = locationComponents[0]
			venueState = locationComponents[1]
			venueName = nil
			schedules = nil
		} else {
			let venueContainer = try? container.nestedContainer(keyedBy: VenueKeys.self, forKey: .venue)
			let venue = try container.decodeIfPresent(Venue.self, forKey: .venues)

			name = try container.decode(String.self, forKey: .name)
			slug = try container.decode(String.self, forKey: .slug)
			startDate = try container.decode(String.self, forKey: .startDate)
			startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
			venueAddress = try container.decodeIfPresent(String.self, forKey: .venueAddress) ?? venueContainer?.decode(String.self, forKey: .address)
			venueZIP = try container.decodeIfPresent(String.self, forKey: .venueZIP) ?? venueContainer?.decode(String.self, forKey: .zipCode)
			venueCity = try container.decodeIfPresent(String.self, forKey: .venueCity) ?? container.decode(String.self, forKey: .locationCity)
			venueState = try container.decodeIfPresent(String.self, forKey: .venueState) ?? container.decode(String.self, forKey: .locationState)
			venueName = try venue.map(\.name) ?? venueContainer!.decode(String.self, forKey: .name)
			schedules = try container.decodeIfPresent([Schedule].self, forKey: .schedules)
		}
		
		let deletedName = venueName?.deleted(from: .venues)
		if var name = deletedName ?? venueName?
			.normalized(from: .venues)
			.replacingOccurrences(of: "  ", with: " ")
			.replacingOccurrences(of: " - ", with: " at ")
			.replacingOccurrences(of: "Univ.", with: "University")
			.replacingOccurrences(of: "(HS|H\\.S\\.)", with: "High School", options: .regularExpression)
			.replacingOccurrences(of: "State$", with: "State University", options: .regularExpression)
			.replacingOccurrences(of: " ([A-Z]) ", with: " $1. ", options: .regularExpression) {
			
			if !name.contains(" at ") {
				name = name.replacingOccurrences(of: "^(.*) (High School|College|University).*$", with: "$1 $2 Stadium at $1 $2", options: .regularExpression)
			}
			
			let components = name.components(separatedBy: " at ")
			if let host = String.inserted(for: name.normalized(from: .venues), from: .venues) {
				venueHost = host
			} else if components.count > 1 && deletedName == nil {
				venueName = components[0].normalized(from: .venues)
				venueHost = components[1].normalized(from: .venues)
			} else {
				venueHost = nil
			}
		} else {
			venueHost = nil
		}
		
		self.init(
			name: name
				.replacingOccurrences(of: "'", with: "’")
			 .replacingOccurrences(of: "  ", with: " ")
			 .replacingOccurrences(of: "- ", with: "– ")
			 .replacingOccurrences(of: "Brass: ", with: "Brass – ")
			 .replacingOccurrences(of: "Champions: ", with: "Champions – ")
			 .replacingOccurrences(of: "([a-z])– ", with: "$1 – ", options: .regularExpression)
			 .replacingOccurrences(of: " @.*", with: "", options: .regularExpression)
			 .replacingOccurrences(of: "(, )?[Pp]resented.*", with: "", options: .regularExpression)
			 .replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression)
			 .normalized(from: .shows),
			slug: slug,
			startDate: startDate,
			startTime: startTime,
			timeZone: timeZone,
			venueAddress: venueAddress?
				.replacingOccurrences(of: "Road", with: "Rd")
			 .replacingOccurrences(of: "Lane", with: "Ln")
			 .replacingOccurrences(of: "Drive", with: "Dr")
			 .replacingOccurrences(of: "Place", with: "Pl")
			 .replacingOccurrences(of: "Street", with: "St")
			 .replacingOccurrences(of: "Avenue", with: "Ave")
			 .replacingOccurrences(of: "Highway", with: "Hwy")
			 .replacingOccurrences(of: "Parkway", with: "Pkwy")
			 .replacingOccurrences(of: "Boulevard", with: "Blvd")
			 .replacingOccurrences(of: "(\\.| \\(.*\\))", with: "", options: .regularExpression)
			 .normalized(from: .addresses),
			venueZIP: venueZIP,
			venueCity: venueCity
				.normalized(from: .locations),
			venueState: venueState,
			venueName: venueName?
				.replacingOccurrences(of: "'", with: "’")
			 .normalized(from: .venues),
			venueHost: venueHost,
			schedules: schedules
		)
	}
}

private extension Event {
	enum CodingKeys: CodingKey {
		case name
		case eventName
		case slug
		case date
		case startDate
		case startTime
		case timeZone
		case venueAddress
		case venueZIP
		case venueCity
		case venueState
		case venue
		case venues
		case location
		case locationCity
		case locationState
		case schedules
	}

	enum VenueKeys: String, CodingKey {
		case name
		case address
		case zipCode = "zioPostcode"
	}

	enum VenuesKeys: String, CodingKey {
		case name
	}
}
