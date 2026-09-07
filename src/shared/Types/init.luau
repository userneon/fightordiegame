--!strict
--[[
	Types
	-----
	Canonical Luau type definitions shared by server and client.

		local Types = require(ReplicatedStorage.Shared.Types)
		type Faction = Types.Faction

	Definitions only — this module holds no data and no logic. Gameplay
	definitions live in Shared/Data, tuning lives in Shared/Config.
]]

-- --- identity ---------------------------------------------------------------

export type Faction = "Army" | "Terrorist" | "Neutral"

export type Zone = "Head" | "Chest" | "Abdomen" | "Arms" | "Legs" | "Feet"

-- Character life-cycle state machine (PlayerService owns transitions):
--   Alive -> Wounded -> Critical -> Dead, with Bleeding as a parallel flag.
export type HealthState = "Alive" | "Wounded" | "Critical" | "Dead"

export type PlayerState = {
	faction: Faction,
	role: string,
	rankTier: number,
	health: HealthState,
	bleeding: number, -- bleed rate; 0 = not bleeding
	deployed: boolean,
	downedAt: number?, -- os.clock() when they entered Wounded/Critical
	carriedBy: Player?,
	carrying: Player?,
}

-- --- lifecycle contract -----------------------------------------------------

-- Every server Service / client Controller implements this. The bootstrap runs
-- Init() on all, then Start() on all, so services may reference each other.
export type Service = {
	Name: string,
	Init: (self: any) -> ()?,
	Start: (self: any) -> ()?,
}

-- --- inventory --------------------------------------------------------------

export type ItemStack = {
	itemId: string,
	count: number,
	-- Per-instance state (helmet durability, magazine contents, battery…).
	state: { [string]: any }?,
}

export type Inventory = {
	Primary: ItemStack?,
	Secondary: ItemStack?,
	Head: ItemStack?,
	Chest: ItemStack?,
	Backpack: ItemStack?,
	-- Free storage; capacity comes from the equipped backpack.
	items: { ItemStack },
}

-- --- combat -----------------------------------------------------------------

export type ShotRequest = {
	weaponId: string,
	origin: Vector3,
	direction: Vector3,
	-- Client's own timestamp; the server only uses it to reject reordering,
	-- never to trust timing.
	clientTime: number,
	seed: number?,
}

export type HitResult = {
	instance: BasePart?,
	position: Vector3,
	normal: Vector3,
	distance: number,
	material: Enum.Material,
	-- Set when the trace resolved onto a character.
	victim: Player?,
	zone: Zone?,
}

export type DamageInfo = {
	amount: number,
	zone: Zone,
	attacker: Player?,
	weaponId: string?,
	ammoId: string?,
	distance: number,
	penetrated: boolean,
	absorbedByArmor: number,
}

-- --- corpses ----------------------------------------------------------------

export type Corpse = {
	id: number,
	ownerUserId: number,
	ownerName: string,
	faction: Faction,
	position: Vector3,
	createdAt: number,
	model: Model?,
	loot: { ItemStack },
	searchedBy: { [number]: boolean },
}

-- --- persistence ------------------------------------------------------------

export type Profile = {
	version: number,
	userId: number,
	xp: number,
	rankTier: number,
	faction: Faction,
	role: string,
	stats: { [string]: number },
	unlocks: { [string]: boolean },
	settings: { [string]: any },
	inventory: Inventory?,
}

-- --- missions ---------------------------------------------------------------

export type ObjectiveState = "Inactive" | "Active" | "InProgress" | "Complete" | "Failed"

export type Objective = {
	id: string,
	kind: string, -- "HoldE" | "Capture" | "Extract" | custom
	state: ObjectiveState,
	progress: number, -- 0..1
	duration: number, -- seconds of hold required
	faction: Faction?,
	holders: { [number]: number }, -- userId -> progress start time
}

return {}
