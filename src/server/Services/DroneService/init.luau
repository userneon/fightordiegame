--!strict
--[[
	DroneService (server-authoritative)
	-----------------------------------
	Recon drone framework. *** BUILDS NO DRONE MODEL. *** You supply the drone
	model (a template you build, referenced by attribute or tag); this service
	owns deployment limits, battery, range and signal state.

	Owns: one drone per operator, battery drain, maximum altitude and range from
	the operator, and signal loss when either is exceeded. The operator's own
	character is left where it stands and cannot fight while flying — the drone
	is a commitment, not a free camera.

	Like Eagle Eye, what the drone REPORTS is decided server-side, so a modified
	client cannot read contacts the drone has not legitimately seen.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)

local DroneService = {}
DroneService.Name = "DroneService"

local log = Logger.scope(DroneService.Name)

type Drone = {
	operator: Player,
	position: Vector3,
	battery: number,
	deployedAt: number,
	signalLost: boolean,
}

function DroneService:Init()
	self._config = Config.Drone
	self._drones = {} :: { [Player]: Drone }
	self._accumulator = 0
end

function DroneService:get(player: Player): Drone?
	return self._drones[player]
end

function DroneService:isFlying(player: Player): boolean
	return self._drones[player] ~= nil
end

-- --- deploy / recall --------------------------------------------------------

function DroneService:deploy(player: Player): (boolean, string?)
	if self._drones[player] then
		return false, "drone already deployed"
	end
	local players = Registry.expect("PlayerService")
	if not players:canFight(player) then
		return false, "unable"
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, "no character"
	end

	self._drones[player] = {
		operator = player,
		position = root.Position + Vector3.new(0, 8, 0),
		battery = self._config.BatteryTime,
		deployedAt = os.clock(),
		signalLost = false,
	}
	player:SetAttribute("DroneActive", true)
	self._stateEvent:FireClient(player, true, self._config.BatteryTime, false)
	log.info(string.format("%s deployed a drone", player.Name))
	return true, nil
end

function DroneService:recall(player: Player, reason: string?)
	if not self._drones[player] then
		return
	end
	self._drones[player] = nil
	player:SetAttribute("DroneActive", false)
	self._stateEvent:FireClient(player, false, 0, false, reason)
end

-- --- control ----------------------------------------------------------------

-- The client flies the drone; the server clamps it. Position is accepted only
-- within the legal envelope, so a client cannot fly across the whole map.
function DroneService:setPosition(player: Player, position: Vector3)
	local drone = self._drones[player]
	if not drone or typeof(position) ~= "Vector3" then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		self:recall(player, "operator lost")
		return
	end

	-- Altitude ceiling.
	local clamped = Vector3.new(position.X, math.min(position.Y, self._config.MaxAltitude), position.Z)

	-- Range from the operator: beyond it the signal is lost, not teleported.
	local distance = (Vector3.new(clamped.X, 0, clamped.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
	if distance > self._config.MaxRange then
		if not drone.signalLost then
			drone.signalLost = true
			self._stateEvent:FireClient(player, true, drone.battery, true, "signal lost")
		end
		return -- refuse the move
	elseif drone.signalLost then
		drone.signalLost = false
		self._stateEvent:FireClient(player, true, drone.battery, false)
	end

	drone.position = clamped
end

-- --- tick -------------------------------------------------------------------

function DroneService:_tick(dt: number)
	local players = Registry.expect("PlayerService")
	for player, drone in self._drones do
		if not player.Parent or not players:canFight(player) then
			self:recall(player, "operator down")
			continue
		end
		drone.battery -= dt
		if drone.battery <= 0 then
			self:recall(player, "battery depleted")
		end
	end
end

function DroneService:Start()
	self._stateEvent = Remotes.getEvent("Drone", "DroneState")

	Remotes.getEvent("Drone", "RequestDeploy").OnServerEvent:Connect(function(player, deploy)
		if deploy == false then
			self:recall(player, "recalled")
		else
			self:deploy(player)
		end
	end)
	Remotes.getEvent("Drone", "DroneInput").OnServerEvent:Connect(function(player, position)
		self:setPosition(player, position)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._drones[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		self._accumulator += dt
		if self._accumulator < 1 then
			return
		end
		local step = self._accumulator
		self._accumulator = 0
		self:_tick(step)
	end)

	log.info("online — drone deployment, battery, range/signal authority")
end

return DroneService
