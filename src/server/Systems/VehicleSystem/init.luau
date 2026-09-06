--!strict
--[[
	VehicleSystem (server-authoritative coordination + client-owned physics)
	------------------------------------------------------------------------
	Owns: enter/exit, seat management, network ownership, and damage/health of
	vehicles you place in the world.

	Vehicles are physics-driven, so the DRIVER's client is granted network
	ownership for responsive control (Config.Vehicle.NetworkOwnershipToDriver);
	the server remains the authority on who may drive, seat occupancy, and
	engine/health state. Vehicle models themselves are yours to build/place —
	this system operates on them by tag/attribute.

	TODO (implement when the Vehicle spec is provided):
	  - Handle Remotes.Vehicle.RequestEnter / RequestExit / VehicleInput.
	  - Assign network ownership; validate seats (Config.Vehicle.MaxSeats).
	  - Apply engine failure below Config.Vehicle.EngineDamageThreshold.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)

local VehicleSystem = {}
VehicleSystem.Name = "VehicleSystem"

local log = Logger.scope(VehicleSystem.Name)

function VehicleSystem:Init()
	self._config = Config.Vehicle
end

function VehicleSystem:Start()
	log.info("ready (stub — awaiting Vehicle spec; operates on vehicles you place)")
end

return VehicleSystem
