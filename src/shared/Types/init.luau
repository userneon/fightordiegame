--!strict
--[[
	Types
	-----
	Shared Luau type definitions used across systems. Import with:
		local Types = require(ReplicatedStorage.Shared.Modules) -- (see note)
	or reference the exported types directly where this module is required.

	Note: Luau exported types are consumed via `require`d module + `.TypeName`
	only in some toolchains; for editor support most teams also duplicate the
	key type aliases where used. Keep this file as the canonical definition.
]]

export type Team = "Army" | "Terrorist" | "Neutral"

export type HealthState = "Healthy" | "Wounded" | "Dead"

-- A lightweight lifecycle contract every server System / client Controller
-- implements. The bootstrap calls Init() on all modules, then Start() on all.
export type System = {
	Name: string,
	Init: (self: System) -> (),
	Start: (self: System) -> (),
}

export type ItemDef = {
	id: string,
	displayName: string,
	weight: number, -- kg, feeds Movement weight -> speed
	stackable: boolean,
	maxStack: number?,
}

export type InventoryEntry = {
	itemId: string,
	count: number,
}

return {}
