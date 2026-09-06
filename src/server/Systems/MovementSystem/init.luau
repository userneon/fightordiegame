--!strict
--[[
	MovementSystem (server-authoritative)
	-------------------------------------
	Owns: Heavy Walk + Inventory-weight -> movement-speed.

	The server is the authority on WalkSpeed. It reads a player's total carried
	weight (from InventorySystem) and applies the speed curve from Config.Movement.
	Clients only *request* sprint via Remotes.Movement.SetSprint; the server
	validates and applies.

	TODO (implement when the "Heavy Walk" / weight->speed spec is provided):
	  - Subscribe to InventorySystem weight-changed events.
	  - Compute effective WalkSpeed = clamp(base/sprint - penalty(weight)).
	  - Toggle a "HeavyWalk" attribute above Config.Movement.HeavyWalkThreshold
	    so the client can play the heavy animation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)

local MovementSystem = {}
MovementSystem.Name = "MovementSystem"

local log = Logger.scope(MovementSystem.Name)

function MovementSystem:Init()
	self._config = Config.Movement
end

function MovementSystem:Start()
	log.info("ready (stub — awaiting Heavy Walk / weight spec)")
end

return MovementSystem
