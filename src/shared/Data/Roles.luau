--!strict
--[[
	Data.Roles
	----------
	Battlefield roles. DATA ONLY.

	A role is orthogonal to rank: rank is authority, role is job. Only a MEDIC
	may treat/revive (per spec) — ordinary soldiers cannot heal each other, so
	`canTreat` is the single source of truth MedicalService checks.

	respawnMultiplier scales the faction's base respawn time (Army medics are
	deliberately slower to return, so losing one hurts).
]]

export type RoleDef = {
	id: string,
	title: string,
	canTreat: boolean, -- may bandage / revive others
	canReviveSelf: boolean,
	respawnMultiplier: number,
	-- Per-slot loadout allowances (InventoryService enforces).
	maxMedicalItems: number,
}

local Roles = {}

Roles.List = {
	Soldier = {
		id = "Soldier",
		title = "SOLDIER",
		canTreat = false,
		canReviveSelf = false,
		respawnMultiplier = 1,
		maxMedicalItems = 2,
	},
	Medic = {
		id = "Medic",
		title = "MEDIC",
		canTreat = true,
		canReviveSelf = false,
		respawnMultiplier = 2, -- longer respawn (Army rule; applies to both)
		maxMedicalItems = 8,
	},
	Engineer = {
		id = "Engineer",
		title = "ENGINEER",
		canTreat = false,
		canReviveSelf = false,
		respawnMultiplier = 1,
		maxMedicalItems = 2,
	},
	Pilot = {
		id = "Pilot",
		title = "PILOT",
		canTreat = false,
		canReviveSelf = false,
		respawnMultiplier = 1.5,
		maxMedicalItems = 2,
	},
} :: { [string]: RoleDef }

Roles.Default = "Soldier"

function Roles.get(id: string?): RoleDef
	return Roles.List[id or Roles.Default] or Roles.List[Roles.Default]
end

function Roles.canTreat(id: string?): boolean
	return Roles.get(id).canTreat
end

return Roles
