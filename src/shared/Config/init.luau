--!strict
--[[
	Config
	------
	Central, tunable constants for every gameplay system in FIGHT OR DIE.

	Keep ALL magic numbers here instead of scattering them across systems.
	Both the server and client require this module, so it must contain data
	only (no side effects, no service access).
]]

local Config = {}

-- ===========================================================================
-- MOVEMENT  (Heavy Walk + Inventory weight -> speed)
-- ===========================================================================
Config.Movement = {
	BaseWalkSpeed = 16, -- Roblox default
	SprintSpeed = 22,
	-- Weight -> speed. Speed is reduced as carried weight approaches the cap.
	MaxCarryWeight = 40, -- kg (soft cap; above this, heavy penalty)
	MinWalkSpeed = 6, -- speed floor when fully overloaded
	HeavyWalkThreshold = 25, -- kg at which "Heavy Walk" state engages
	SpeedPenaltyPerKg = 0.25, -- studs/s lost per kg over threshold
}

-- ===========================================================================
-- HEALTH / WOUNDED / BLEEDING
-- ===========================================================================
Config.Health = {
	MaxHealth = 100,
	-- Below this fraction of health the player enters the "Wounded" (downed) state
	-- instead of dying outright.
	WoundedThreshold = 0.0, -- 0 = enter wounded at 0 HP (bleed-out timer starts)
	BleedOutTime = 90, -- seconds a wounded player survives before dying
	BleedDamagePerTick = 1,
	BleedTickInterval = 1, -- seconds
	ReviveTime = 8, -- seconds a medic must channel to revive
	ReviveHealth = 35, -- HP restored on successful revive
}

-- ===========================================================================
-- MEDIC
-- ===========================================================================
Config.Medic = {
	HealPerBandage = 25,
	BandageUseTime = 4, -- seconds
	MaxHealDistance = 8, -- studs medic must be within to treat a teammate
}

-- ===========================================================================
-- CARRY  (carrying downed/wounded players)
-- ===========================================================================
Config.Carry = {
	MaxCarryDistance = 6, -- studs to start a carry
	CarrySpeedMultiplier = 0.6, -- carrier moves slower
	CanCarryWhileWounded = false,
}

-- ===========================================================================
-- INVENTORY  (+ corpse search)
-- ===========================================================================
Config.Inventory = {
	MaxSlots = 20,
	CorpseSearchTime = 3, -- seconds
	CorpseDespawnTime = 300, -- seconds before a searchable corpse is removed
}

-- ===========================================================================
-- SPAWN / RESPAWN
-- ===========================================================================
Config.Spawn = {
	RespawnTime = 10, -- seconds
	-- Team spawn zones are resolved by name at runtime; keep the world-building
	-- ownership with you. These are just the CollectionService tags / names the
	-- SpawnSystem will look for in the map you build.
	ArmySpawnTag = "ArmySpawn",
	TerroristSpawnTag = "TerroristSpawn",
}

-- ===========================================================================
-- VEHICLES
-- ===========================================================================
Config.Vehicle = {
	NetworkOwnershipToDriver = true,
	MaxSeats = 6,
	EngineDamageThreshold = 0.3, -- health fraction below which the engine fails
}

-- ===========================================================================
-- DRONES
-- ===========================================================================
Config.Drone = {
	MaxAltitude = 300, -- studs
	MaxRange = 800, -- studs from operator before signal loss
	BatteryTime = 180, -- seconds of flight
	ControlHz = 20, -- input send rate
}

-- ===========================================================================
-- VISION  (NVG / flashlight / searchlights / blackout)
-- ===========================================================================
Config.Vision = {
	NvgBrightness = 2,
	NvgTint = Color3.fromRGB(120, 255, 120),
	FlashlightRange = 60,
	FlashlightAngle = 45,
	BlackoutAmbient = Color3.fromRGB(5, 5, 8),
}

return Config
