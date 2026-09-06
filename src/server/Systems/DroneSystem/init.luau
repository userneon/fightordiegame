--!strict
--[[
	DroneSystem (server-authoritative coordination + client-owned flight)
	---------------------------------------------------------------------
	Owns: drone deployment, operator binding, battery/range/altitude limits, and
	the operator's camera hand-off.

	Like vehicles, drone flight physics run on the operator's client (granted
	network ownership) for responsiveness, while the server validates deployment,
	enforces Config.Drone limits (MaxAltitude, MaxRange, BatteryTime), and handles
	signal loss / recall.

	TODO (implement when the Drone spec is provided):
	  - Handle Remotes.Drone.RequestDeploy / DroneInput / DroneState.
	  - Enforce range/altitude/battery; force recall or crash on breach.
	  - Manage camera control transfer to/from the operator.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)

local DroneSystem = {}
DroneSystem.Name = "DroneSystem"

local log = Logger.scope(DroneSystem.Name)

function DroneSystem:Init()
	self._config = Config.Drone
end

function DroneSystem:Start()
	log.info("ready (stub — awaiting Drone spec)")
end

return DroneSystem
