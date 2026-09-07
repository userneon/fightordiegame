--!strict
--[[
	Data.Ranks
	----------
	Rank ladders and what each rank is ALLOWED to do. DATA ONLY.

	Design rule (per spec): rank controls AUTHORITY, ACCESS and PERMISSIONS.
	Rank deliberately grants no combat stat bonuses — a General's rifle does
	exactly the same damage as a Private's. Progression buys responsibility,
	not lethality.

	Permissions are additive up the ladder: a rank holds every permission of
	the ranks below it (resolved in RankService), so each entry below only
	lists what that rank ADDS.
]]

export type Permission = string

export type RankDef = {
	tier: number, -- 1..8, higher = more authority
	id: string,
	title: string,
	xpRequired: number,
	-- Permissions this rank ADDS on top of every lower rank.
	grants: { Permission },
}

local Ranks = {}

-- Canonical permission keys. Services check these by name; keep them here so
-- there is one spelling of each.
Ranks.Permissions = {
	-- squad / authority
	CommandSquad = "CommandSquad",
	MarkTargets = "MarkTargets",
	PromoteSquad = "PromoteSquad",
	-- access
	AccessArmory = "AccessArmory",
	AccessRestricted = "AccessRestricted", -- restricted doors / access cards
	AccessCommandPost = "AccessCommandPost",
	-- assets
	DriveVehicle = "DriveVehicle",
	DriveArmor = "DriveArmor",
	PilotHelicopter = "PilotHelicopter",
	-- recon / missions
	UseEagleEye = "UseEagleEye",
	StartMission = "StartMission",
	AbortMission = "AbortMission",
	CallExtraction = "CallExtraction",
}

local P = Ranks.Permissions

-- ARMY ladder (as specified).
Ranks.Army = {
	{ tier = 1, id = "PRIVATE", title = "PRIVATE", xpRequired = 0, grants = { P.DriveVehicle } },
	{ tier = 2, id = "CORPORAL", title = "CORPORAL", xpRequired = 1000, grants = { P.MarkTargets } },
	{ tier = 3, id = "SERGEANT", title = "SERGEANT", xpRequired = 3000, grants = { P.CommandSquad, P.AccessArmory } },
	{ tier = 4, id = "LIEUTENANT", title = "LIEUTENANT", xpRequired = 7000, grants = { P.StartMission, P.DriveArmor } },
	{ tier = 5, id = "CAPTAIN", title = "CAPTAIN", xpRequired = 13000, grants = { P.UseEagleEye, P.AccessRestricted } },
	{ tier = 6, id = "MAJOR", title = "MAJOR", xpRequired = 22000, grants = { P.PilotHelicopter, P.CallExtraction } },
	{ tier = 7, id = "COLONEL", title = "COLONEL", xpRequired = 35000, grants = { P.AbortMission, P.AccessCommandPost } },
	{ tier = 8, id = "GENERAL", title = "GENERAL", xpRequired = 55000, grants = { P.PromoteSquad } },
} :: { RankDef }

-- TERRORIST ladder. Mirrors the Army authority tiers so both factions share one
-- progression curve. Titles are yours to rename — they are pure data.
Ranks.Terrorist = {
	{ tier = 1, id = "RECRUIT", title = "RECRUIT", xpRequired = 0, grants = { P.DriveVehicle } },
	{ tier = 2, id = "FIGHTER", title = "FIGHTER", xpRequired = 1000, grants = { P.MarkTargets } },
	{ tier = 3, id = "VETERAN", title = "VETERAN", xpRequired = 3000, grants = { P.CommandSquad, P.AccessArmory } },
	{ tier = 4, id = "LEADER", title = "LEADER", xpRequired = 7000, grants = { P.StartMission, P.DriveArmor } },
	{ tier = 5, id = "COMMANDER", title = "COMMANDER", xpRequired = 13000, grants = { P.AccessRestricted } },
	{ tier = 6, id = "WARLORD", title = "WARLORD", xpRequired = 22000, grants = { P.CallExtraction } },
	{ tier = 7, id = "CHIEF", title = "CHIEF", xpRequired = 35000, grants = { P.AbortMission, P.AccessCommandPost } },
	{ tier = 8, id = "SHADOW", title = "SHADOW", xpRequired = 55000, grants = { P.PromoteSquad } },
} :: { RankDef }

function Ranks.ladderFor(faction: string): { RankDef }
	if faction == "Terrorist" then
		return Ranks.Terrorist
	end
	return Ranks.Army
end

function Ranks.byTier(faction: string, tier: number): RankDef?
	for _, rank in Ranks.ladderFor(faction) do
		if rank.tier == tier then
			return rank
		end
	end
	return nil
end

-- Highest tier whose xpRequired is satisfied.
function Ranks.tierForXp(faction: string, xp: number): number
	local best = 1
	for _, rank in Ranks.ladderFor(faction) do
		if xp >= rank.xpRequired and rank.tier > best then
			best = rank.tier
		end
	end
	return best
end

return Ranks
