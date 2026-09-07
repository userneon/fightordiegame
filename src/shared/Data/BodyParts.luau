--!strict
--[[
	Data.BodyParts
	--------------
	Body-part hit zones and their damage behaviour. DATA ONLY.

	Maps the Roblox character part that a ballistic ray actually hit (R15 and R6
	names both covered) onto a logical zone, so DamageService never has to care
	which rig the character uses.

	Zones (per spec): Head / Chest / Abdomen / Arms / Legs / Feet.

	`multiplier`  — damage scale for that zone.
	`armorable`   — a helmet can absorb this hit (head only).
	`bleedRate`   — bleeding added per hit (Health config scales it).
	`critical`    — hits here can drive the CRITICAL state, not just wounded.
]]

export type Zone = "Head" | "Chest" | "Abdomen" | "Arms" | "Legs" | "Feet"

export type ZoneDef = {
	id: Zone,
	multiplier: number,
	armorable: boolean,
	bleedRate: number,
	critical: boolean,
}

local BodyParts = {}

BodyParts.Zones = {
	Head = { id = "Head" :: Zone, multiplier = 4.0, armorable = true, bleedRate = 3.0, critical = true },
	Chest = { id = "Chest" :: Zone, multiplier = 1.0, armorable = false, bleedRate = 1.5, critical = true },
	Abdomen = { id = "Abdomen" :: Zone, multiplier = 0.9, armorable = false, bleedRate = 2.0, critical = true },
	Arms = { id = "Arms" :: Zone, multiplier = 0.65, armorable = false, bleedRate = 1.0, critical = false },
	Legs = { id = "Legs" :: Zone, multiplier = 0.7, armorable = false, bleedRate = 1.2, critical = false },
	Feet = { id = "Feet" :: Zone, multiplier = 0.5, armorable = false, bleedRate = 0.8, critical = false },
} :: { [string]: ZoneDef }

-- Roblox part name -> zone. Covers R15 and R6 rigs.
local PART_TO_ZONE: { [string]: Zone } = {
	-- shared
	Head = "Head",
	-- R15 torso
	UpperTorso = "Chest",
	LowerTorso = "Abdomen",
	-- R6 torso (single part — treated as chest)
	Torso = "Chest",
	-- R15 arms
	LeftUpperArm = "Arms",
	LeftLowerArm = "Arms",
	LeftHand = "Arms",
	RightUpperArm = "Arms",
	RightLowerArm = "Arms",
	RightHand = "Arms",
	-- R6 arms
	["Left Arm"] = "Arms",
	["Right Arm"] = "Arms",
	-- R15 legs
	LeftUpperLeg = "Legs",
	LeftLowerLeg = "Legs",
	RightUpperLeg = "Legs",
	RightLowerLeg = "Legs",
	-- R15 feet
	LeftFoot = "Feet",
	RightFoot = "Feet",
	-- R6 legs
	["Left Leg"] = "Legs",
	["Right Leg"] = "Legs",
}

-- Resolve a hit part name to a zone. Unknown parts (accessories, tools,
-- attachments) fall back to Chest so damage is never silently dropped.
function BodyParts.zoneForPart(partName: string): Zone
	return PART_TO_ZONE[partName] or "Chest"
end

function BodyParts.get(zone: Zone): ZoneDef
	return BodyParts.Zones[zone] or BodyParts.Zones.Chest
end

return BodyParts
