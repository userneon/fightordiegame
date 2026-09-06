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
	-- Base speeds (studs/s)
	BaseWalkSpeed = 16, -- Roblox default
	SprintSpeed = 24,
	CrouchSpeed = 8,
	MinWalkSpeed = 6, -- absolute speed floor when fully overloaded

	-- Jump (we use JumpPower so it can be tuned/penalised by state)
	JumpPower = 50,
	CrouchJumpPower = 0, -- no jumping while crouched

	-- Weight -> speed. Speed is reduced as carried weight passes the threshold.
	MaxCarryWeight = 40, -- kg (soft cap; at/above this, maximum penalty)
	HeavyWalkThreshold = 25, -- kg at which the "Heavy Walk" state engages
	SpeedPenaltyPerKg = 0.25, -- studs/s lost per kg over HeavyWalkThreshold

	-- Stamina (sprinting consumes it; it regenerates when not sprinting)
	MaxStamina = 100,
	SprintStaminaDrain = 12, -- per second while sprinting
	StaminaRegen = 14, -- per second while recovering
	StaminaRegenDelay = 1.2, -- seconds after sprint stops before regen begins
	SprintMinStamina = 5, -- need at least this much stamina to *start* sprinting
	HeavyStaminaDrainMultiplier = 1.8, -- sprint drains faster while over Heavy threshold

	-- Update rate of the server movement loop (seconds). Lower = smoother
	-- stamina/speed, slightly more work. Heartbeat-driven, so this is a throttle.
	UpdateInterval = 0.1,
}

-- ===========================================================================
-- ANIMATION  (client, feel-only — driven by server state attributes)
-- ===========================================================================
Config.Animation = {
	-- Heavy Walk: a slower, laboured stride played locally when the server sets
	-- the "HeavyWalk" attribute (weight >= HeavyWalkThreshold). Authored assets
	-- live with the NOMAD BROS team; drop the published Animation asset id here
	-- (e.g. "rbxassetid://1234567890"). Leave "" to keep the controller dormant
	-- until the asset exists — it degrades gracefully rather than erroring.
	HeavyWalkAnimationId = "",

	-- Plays above Roblox's default Core-priority walk/run so it overrides it.
	HeavyWalkPriority = Enum.AnimationPriority.Movement,

	-- Cross-fade times (seconds) when the heavy stride starts / stops.
	HeavyWalkFadeIn = 0.25,
	HeavyWalkFadeOut = 0.2,

	-- Only animate once the character is genuinely moving (MoveDirection magnitude).
	MoveThreshold = 0.05,

	-- The stride is authored for this walk speed (studs/s). Playback speed is
	-- scaled by actual WalkSpeed / this so feet don't slide as weight bites.
	HeavyWalkReferenceSpeed = 16,
	MinPlaybackSpeed = 0.5,
	MaxPlaybackSpeed = 1.5,
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
-- CAMERA  (gameplay is first-person only; client-only)
-- ===========================================================================
Config.Camera = {
	-- Normal gameplay is hard-locked to first person. The menu / vehicle /
	-- spectator cameras are separate modes owned elsewhere, so this only governs
	-- the on-foot gameplay camera.
	GameplayFieldOfView = 70, -- reset from the menu's cinematic FOV on deploy

	-- First-person body awareness: render the local character in first person so
	-- weapon / hand / body / interaction animations are actually visible (Roblox
	-- otherwise hides the body and shows only tool arms).
	FirstPersonBody = true,
	-- Hide the head + hat/hair/face accessories locally so the camera isn't
	-- inside the head mesh. Body, arms, and legs stay visible.
	HideHeadInFirstPerson = true,
}

-- ===========================================================================
-- HUD  (client-only heads-up display tuning)
-- ===========================================================================
Config.HUD = {
	-- Open compass strip (no box/panel — draws directly over the world and fades
	-- toward both edges). Reused by any faction HUD via the Compass component.
	Compass = {
		Width = 460, -- px, total strip width
		Height = 46, -- px
		Y = 14, -- px from the top of the screen
		SpanDegrees = 140, -- total degrees of heading visible across the width
		TickSpacing = 15, -- a tick + number every N degrees (letters at 45s)
		Smoothing = 10, -- heading lerp rate; higher = snappier, lower = floatier
		FadeStart = 0.4, -- 0..1 of the half-width that stays fully opaque before fading
	},
}

-- ===========================================================================
-- MENU  (Start Menu UI + menu camera; client-only presentation)
-- ===========================================================================
Config.Menu = {
	-- Branding / text
	Title = "FIGHT OR DIE",
	Subtitle = "A NOMAD BROS GAME",
	Tagline = "DISCIPLINE / BROTHERHOOD / SURVIVE",
	Platform = "PC ONLY",
	Version = "v0.1.0",
	Studio = "NOMAD BROS",

	-- Player info fallbacks. Rank has no backing system yet; the menu reads the
	-- player attribute "Rank" and falls back to this. Team reads player.Team,
	-- then the "MenuTeam" attribute, then this.
	DefaultRank = "PRIVATE I",
	DefaultTeam = "UNASSIGNED",

	-- Menu camera. The world (Army Base, etc.) is built by the NOMAD BROS team,
	-- not this repo, so the camera resolves against optional tagged/named parts
	-- in your map and degrades to a gentle orbit near the origin if none exist.
	--   * A part named CameraAnchorName -> the camera sits at it (with light sway)
	--   * A part named CameraTargetName -> the camera looks at it
	CameraAnchorName = "MenuCamera",
	CameraTargetName = "MenuCameraTarget",
	CameraFieldOfView = 55,

	-- Orbit fallback (used when no anchor part is found).
	CameraOrbitCenter = Vector3.new(0, 6, 0),
	CameraOrbitRadius = 22,
	CameraOrbitHeight = 7,
	CameraOrbitSpeed = 0.035, -- radians/sec — slow drift
	CameraLookHeight = 4,

	-- Sway applied when an anchor part IS found (keeps the shot alive).
	CameraSwayAmount = 1.5, -- studs
	CameraSwaySpeed = 0.25, -- radians/sec

	-- Hover / selection transition time (seconds).
	TransitionTime = 0.15,
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
