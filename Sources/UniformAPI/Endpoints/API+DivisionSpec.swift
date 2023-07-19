// Copyright © Fleuronic LLC. All rights reserved.

import struct Diesel.Division
import struct DieselService.IdentifiedDivision
import protocol UniformService.DivisionSpec
import protocol Catenary.API

extension API: DivisionSpec {
    public func find(_ division: Division) async -> Self.Result<Division.Identified> {
        await fetch(where: division.matches).asyncFlatMap { ids in
            await ids.first.map { id in
                .success(division.identified(id: id))
            }.asyncMapNil {
                let division = division.identified()
                return await insert(division).map { _ in division }
            }
        }
    }
}
