--!strict
--[[
	CarrySystem (server-authoritative)
	----------------------------------
	Owns: carrying downed/wounded players (fireman's carry).

	The server validates a carry request (target is wounded, within
	Config.Carry.MaxCarryDistance, carrier is not themselves wounded), then welds
	the carried character to the carrier and applies a speed multiplier via
	MovementSystem. Dropping releases the weld.

	TODO (implement when the Carry spec is provided):
	  - Handle Remotes.Carry.RequestCarry / RequestDrop.
	  - Manage the weld + collision + network ownership of the carried character.
	  - Coordinate with MovementSystem (CarrySpeedMultiplier) and WoundedSystem.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)

local CarrySystem = {}
CarrySystem.Name = "CarrySystem"

local log = Logger.scope(CarrySystem.Name)

function CarrySystem:Init()
	self._config = Config.Carry
	self._active = {} -- [carrier Player] = carried Player
end

function CarrySystem:Start()
	log.info("ready (stub — awaiting Carry spec)")
end

return CarrySystem
