--!strict
--[[
	WoundedSystem (server-authoritative)
	------------------------------------
	Owns: the downed / wounded / bleeding state machine.

	When a player's HP would reach the wounded threshold, instead of dying they
	enter the Wounded state: immobilised, bleeding out over Config.Health.BleedOutTime.
	A medic (MedicSystem) or teammate can revive them; otherwise they die when the
	bleed-out timer expires.

	Exposes (to other systems via this module table once implemented):
	  - :isWounded(player)
	  - :setWounded(player, bool)
	  - a signal/event other systems can listen to for state changes.

	TODO (implement when the Wounded/Bleeding spec is provided):
	  - Intercept Humanoid.HealthChanged / Died.
	  - Drive the bleed tick loop (Config.Health.BleedTickInterval).
	  - Replicate state via Remotes.Wounded.StateChanged / BleedTick.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)

local WoundedSystem = {}
WoundedSystem.Name = "WoundedSystem"

local log = Logger.scope(WoundedSystem.Name)

function WoundedSystem:Init()
	self._config = Config.Health
	self._wounded = {} -- [Player] = { startTime = number }
end

function WoundedSystem:Start()
	log.info("ready (stub — awaiting Wounded/Bleeding spec)")
end

return WoundedSystem
