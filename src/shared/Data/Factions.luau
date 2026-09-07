--!strict
--[[
	Data.Factions
	-------------
	Faction definitions. DATA ONLY — no logic, no services, no side effects.
	FactionService reads this; edit here to retune, never in the service.

	SpawnTag / corpse and loot rules are expressed as data so the world you
	build in Studio connects by tag — this file never touches map geometry.
]]

export type FactionId = "Army" | "Terrorist" | "Neutral"

export type FactionDef = {
	id: FactionId,
	displayName: string,
	-- CollectionService tag on the spawn zones YOU place in the map.
	spawnTag: string,
	-- Respawn timing (seconds). Medic override lives in Ranks/roles config.
	respawnTime: number,
	-- Can members of this faction loot weapons/equipment from ENEMY corpses?
	canLootEnemyWeapons: boolean,
	-- Can they always take mission-critical items off an enemy corpse?
	canLootEnemyMissionItems: boolean,
	-- Abilities gated to a whole faction (rank gates the rest).
	abilities: { [string]: boolean },
}

local Factions = {}

Factions.List = {
	Army = {
		id = "Army" :: FactionId,
		displayName = "ARMY",
		spawnTag = "ArmySpawn",
		respawnTime = 15,
		canLootEnemyWeapons = false,
		canLootEnemyMissionItems = true,
		abilities = {
			EagleEye = true, -- Army-only recon (see EagleEyeService)
			Helicopter = true,
		},
	},
	Terrorist = {
		id = "Terrorist" :: FactionId,
		displayName = "TERRORIST",
		spawnTag = "TerroristSpawn",
		respawnTime = 5, -- faster per game rules
		canLootEnemyWeapons = false,
		canLootEnemyMissionItems = true,
		abilities = {
			EagleEye = false,
			Helicopter = false,
		},
	},
	Neutral = {
		id = "Neutral" :: FactionId,
		displayName = "UNASSIGNED",
		spawnTag = "NeutralSpawn",
		respawnTime = 10,
		canLootEnemyWeapons = false,
		canLootEnemyMissionItems = false,
		abilities = {},
	},
} :: { [string]: FactionDef }

-- The factions a player may actually be assigned to (Neutral is the pre-deploy
-- holding state, not a playable side).
Factions.Playable = { "Army", "Terrorist" }

function Factions.get(id: string): FactionDef?
	return Factions.List[id]
end

function Factions.isPlayable(id: string): boolean
	return id == "Army" or id == "Terrorist"
end

function Factions.areEnemies(a: string, b: string): boolean
	if not Factions.isPlayable(a) or not Factions.isPlayable(b) then
		return false
	end
	return a ~= b
end

return Factions
