--!strict
--[[
	Data.Ammo
	---------
	Cartridge/calibre ballistics. DATA ONLY.

	These feed BallisticsService's simulation directly:
	  muzzleVelocity — studs/second at the barrel
	  drag           — per-second fractional velocity loss (air resistance)
	  gravity        — studs/s^2 pulling the round down (bullet drop)
	  penetration    — "power" spent against Material.resistance * thickness
	  maxRange       — studs after which the round is despawned
	  damageFalloff  — {near, far} studs; damage lerps from 1.0 to farMultiplier

	One round is never a physical Part — these numbers are integrated in code.
]]

export type AmmoDef = {
	id: string,
	displayName: string,
	baseDamage: number,
	muzzleVelocity: number,
	drag: number,
	gravity: number,
	penetration: number,
	maxRange: number,
	nearRange: number,
	farRange: number,
	farMultiplier: number,
	weight: number, -- kg per round (feeds inventory weight -> movement)
}

local Ammo = {}

Ammo.List = {
	["5.56x45"] = {
		id = "5.56x45",
		displayName = "5.56×45mm",
		baseDamage = 34,
		muzzleVelocity = 900,
		drag = 0.055,
		gravity = 60,
		penetration = 22,
		maxRange = 1200,
		nearRange = 120,
		farRange = 600,
		farMultiplier = 0.6,
		weight = 0.012,
	},
	["7.62x39"] = {
		id = "7.62x39",
		displayName = "7.62×39mm",
		baseDamage = 42,
		muzzleVelocity = 730,
		drag = 0.07,
		gravity = 62,
		penetration = 26,
		maxRange = 1000,
		nearRange = 100,
		farRange = 500,
		farMultiplier = 0.58,
		weight = 0.016,
	},
	["7.62x51"] = {
		id = "7.62x51",
		displayName = "7.62×51mm",
		baseDamage = 55,
		muzzleVelocity = 840,
		drag = 0.05,
		gravity = 60,
		penetration = 34,
		maxRange = 1800,
		nearRange = 200,
		farRange = 900,
		farMultiplier = 0.7,
		weight = 0.024,
	},
	["9x19"] = {
		id = "9x19",
		displayName = "9×19mm",
		baseDamage = 26,
		muzzleVelocity = 380,
		drag = 0.11,
		gravity = 64,
		penetration = 9,
		maxRange = 400,
		nearRange = 40,
		farRange = 160,
		farMultiplier = 0.5,
		weight = 0.009,
	},
	["12ga"] = {
		id = "12ga",
		displayName = "12 Gauge",
		baseDamage = 18, -- per pellet
		muzzleVelocity = 420,
		drag = 0.22,
		gravity = 66,
		penetration = 6,
		maxRange = 250,
		nearRange = 20,
		farRange = 90,
		farMultiplier = 0.3,
		weight = 0.045,
	},
	[".338LM"] = {
		id = ".338LM",
		displayName = ".338 Lapua Magnum",
		baseDamage = 92,
		muzzleVelocity = 950,
		drag = 0.04,
		gravity = 58,
		penetration = 46,
		maxRange = 2500,
		nearRange = 300,
		farRange = 1400,
		farMultiplier = 0.8,
		weight = 0.032,
	},
} :: { [string]: AmmoDef }

function Ammo.get(id: string): AmmoDef?
	return Ammo.List[id]
end

return Ammo
