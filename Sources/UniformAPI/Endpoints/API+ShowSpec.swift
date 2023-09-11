// Copyright © Fleuronic LLC. All rights reserved.

import struct Diesel.Show
import struct DieselService.IdentifiedShow
import protocol UniformService.ShowSpec
import protocol Catenary.API

extension API: ShowSpec {
	public func find(_ show: Show) async -> Self.Result<Show.Identified> {
		await fetch(where: show.matches).asyncFlatMap { ids in
			await ids.first.map(show.identified).map(Result.success).asyncMapNil {
				let show = show.identified()
				return await insert(show).map { _ in show }
			}
		}
	}
}
