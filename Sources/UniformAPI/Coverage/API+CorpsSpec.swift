// Copyright © Fleuronic LLC. All rights reserved.

import Kanna
import Foundation
import Uniform
import struct DrumKit.Corps
import struct DrumKit.Location
import struct DrumKitService.IdentifiedCorps
import protocol Catena.Scoped
import protocol Catena.ResultProviding
import protocol UniformService.CorpsSpec

extension API: CorpsSpec {
	public func listCorps() async -> Results<CorpsSpecifiedFields> {
		do {
			let url = URL(string: "https://www.dcxmuseum.org/corps.cfm")!
			let html = try await scraperSession.string(from: url)
			let doc = try HTML(html: html, encoding: .utf8)
			let corps = doc.xpath("//tr").map { element in
				element.xpath("td").flatMap { element in
					if let anchor = (element.xpath("a").first) {
						let url = anchor["href"]!
						let id =  url
							.components(separatedBy: "=")[2]
							.components(separatedBy: "&")[0]
						return [id, anchor.text!]
					} else {
						return [element.text!]
					}
				}.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			}.filter { !$0.isEmpty && !$0[1].isEmpty }.map { row in
				let location = row[4].isEmpty ? Location.info(for: row[3]) : nil
				return CorpsSpecifiedFields(
					id: .init(rawValue: Int(row[0])!),
					name: row[1],
					city: location?.0 ?? row[3],
					state: location?.1 ?? row[4],
					country: location?.2 ?? row[5]
				)
			}

			return .success(corps)
		} catch {
			return .failure(.network(error as NSError))
		}
	}

	public func fetchCorps(with id: Uniform.Corps.InvalidID) async -> SingleResult<CorpsSpecifiedFields> {
		// Cannot use API to fetch individual corps
	}

	public func fetchCorps(with name: String) async -> SingleResult<CorpsSpecifiedFields> {
		// Cannot use API to fetch individual corps
		fatalError() // TODO
	}

	public func createCorps(named name: String, basedInLocationWith locationID: Location.ID) async -> SingleResult<DrumKit.Corps.ID> {
		await insert(
			CorpsInput(
				name: name,
				locationID: locationID
			)
		)
	}
}
