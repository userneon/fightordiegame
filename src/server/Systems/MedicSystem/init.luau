--!strict
--[[
	MedicSystem (server-authoritative)
	----------------------------------
	Owns: healing and reviving.

	Validates heal/revive requests (distance, line-of-sight, medic has supplies,
	target is a valid teammate / wounded) and applies the result. Works closely
	with WoundedSystem (to revive) and InventorySystem (to consume bandages).

	TODO (implement when the Medic spec is provided):
	  - Handle Remotes.Medic.RequestHeal / RequestRevive.
	  - Enforce Config.Medic.MaxHealDistance and channel times.
	  - Broadcast Remotes.Medic.TreatmentProgress for the client progress bar.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)

local MedicSystem = {}
MedicSystem.Name = "MedicSystem"

local log = Logger.scope(MedicSystem.Name)

function MedicSystem:Init()
	self._config = Config.Medic
end

function MedicSystem:Start()
	log.info("ready (stub — awaiting Medic spec)")
end

return MedicSystem
