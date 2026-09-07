--!strict
--[[
	Data.Weapons
	------------
	Weapon definitions. DATA ONLY — WeaponService contains the logic, this file
	contains every per-weapon number, so adding a gun never means touching code.

	  slot        — which inventory slot it occupies (Primary / Secondary)
	  ammoId      — key into Data.Ammo
	  rpm         — rounds per minute; drives server fire-rate validation
	  fireModes   — allowed selector positions
	  pellets     — >1 for shotguns (one ballistic trace per pellet)
	  spreadMoa   — base cone; the server clamps client aim direction to it
	  reloadTime  — seconds (tactical); reloadEmptyTime when the chamber is dry
	  equipTime   — seconds before the weapon can fire after being drawn
	  weight      — kg, feeds inventory weight -> movement penalty
	  minTier     — minimum rank tier allowed to draw it from the armory
]]

export type FireMode = "Semi" | "Burst" | "Auto" | "Bolt"

export type WeaponDef = {
	id: string,
	displayName: string,
	slot: "Primary" | "Secondary",
	class: string,
	ammoId: string,
	magSize: number,
	rpm: number,
	fireModes: { FireMode },
	burstCount: number,
	pellets: number,
	spreadMoa: number,
	reloadTime: number,
	reloadEmptyTime: number,
	equipTime: number,
	weight: number,
	minTier: number,
}

local Weapons = {}

Weapons.List = {
	M4A1 = {
		id = "M4A1",
		displayName = "M4A1",
		slot = "Primary" :: "Primary",
		class = "AssaultRifle",
		ammoId = "5.56x45",
		magSize = 30,
		rpm = 800,
		fireModes = { "Semi" :: FireMode, "Auto" :: FireMode },
		burstCount = 3,
		pellets = 1,
		spreadMoa = 30,
		reloadTime = 2.4,
		reloadEmptyTime = 3.1,
		equipTime = 0.5,
		weight = 3.4,
		minTier = 1,
	},
	AK74 = {
		id = "AK74",
		displayName = "AK-74",
		slot = "Primary" :: "Primary",
		class = "AssaultRifle",
		ammoId = "7.62x39",
		magSize = 30,
		rpm = 650,
		fireModes = { "Semi" :: FireMode, "Auto" :: FireMode },
		burstCount = 3,
		pellets = 1,
		spreadMoa = 38,
		reloadTime = 2.6,
		reloadEmptyTime = 3.3,
		equipTime = 0.55,
		weight = 3.6,
		minTier = 1,
	},
	M110 = {
		id = "M110",
		displayName = "M110 DMR",
		slot = "Primary" :: "Primary",
		class = "Marksman",
		ammoId = "7.62x51",
		magSize = 20,
		rpm = 380,
		fireModes = { "Semi" :: FireMode },
		burstCount = 1,
		pellets = 1,
		spreadMoa = 14,
		reloadTime = 2.8,
		reloadEmptyTime = 3.6,
		equipTime = 0.7,
		weight = 4.9,
		minTier = 2,
	},
	AWM = {
		id = "AWM",
		displayName = "AWM",
		slot = "Primary" :: "Primary",
		class = "Sniper",
		ammoId = ".338LM",
		magSize = 5,
		rpm = 45,
		fireModes = { "Bolt" :: FireMode },
		burstCount = 1,
		pellets = 1,
		spreadMoa = 6,
		reloadTime = 3.4,
		reloadEmptyTime = 4.2,
		equipTime = 0.9,
		weight = 6.8,
		minTier = 3,
	},
	M870 = {
		id = "M870",
		displayName = "M870",
		slot = "Primary" :: "Primary",
		class = "Shotgun",
		ammoId = "12ga",
		magSize = 7,
		rpm = 75,
		fireModes = { "Semi" :: FireMode },
		burstCount = 1,
		pellets = 8,
		spreadMoa = 320,
		reloadTime = 0.6, -- per shell
		reloadEmptyTime = 0.6,
		equipTime = 0.6,
		weight = 3.9,
		minTier = 1,
	},
	M9 = {
		id = "M9",
		displayName = "M9",
		slot = "Secondary" :: "Secondary",
		class = "Pistol",
		ammoId = "9x19",
		magSize = 15,
		rpm = 450,
		fireModes = { "Semi" :: FireMode },
		burstCount = 1,
		pellets = 1,
		spreadMoa = 55,
		reloadTime = 1.6,
		reloadEmptyTime = 2.2,
		equipTime = 0.3,
		weight = 0.9,
		minTier = 1,
	},
} :: { [string]: WeaponDef }

function Weapons.get(id: string): WeaponDef?
	return Weapons.List[id]
end

-- Seconds between shots implied by RPM — the server's fire-rate gate.
function Weapons.shotInterval(def: WeaponDef): number
	return 60 / math.max(1, def.rpm)
end

function Weapons.hasFireMode(def: WeaponDef, mode: string): boolean
	for _, m in def.fireModes do
		if m == mode then
			return true
		end
	end
	return false
end

return Weapons
