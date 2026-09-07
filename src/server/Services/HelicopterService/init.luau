--!strict
--[[
	HelicopterService (server-authoritative)
	----------------------------------------
	Helicopter FRAMEWORK ONLY. *** BUILDS NO HELICOPTER MODEL. *** You build and
	tag the aircraft; this service owns the authoritative state around it.

	Connect an aircraft you built
	-----------------------------
	  Tag the Model "Helicopter". Optional attributes:
	    MaxHealth, Faction, RequiredPerm (defaults to PilotHelicopter)
	  A VehicleSeat inside the model is the pilot seat; Seats are passengers.

	Owns: helicopter state, pilot/passenger state, damage state, flight-state
	validation (grounded / airborne / falling), radar detection state, target
	tracking, and lock / lost-lock state.

	Flight physics stay on the pilot's client (network ownership) — the server
	validates the RESULTS (altitude ceiling, impossible climb rates) rather than
	simulating the aircraft, which is the practical model for Roblox aircraft.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)
local Data = require(Shared.Data)

local HelicopterService = {}
HelicopterService.Name = "HelicopterService"

local log = Logger.scope(HelicopterService.Name)

local TAG = "Helicopter"
local RADAR_RANGE = 1500
local RADAR_INTERVAL = 1
local LOCK_TIME = 2.5 -- seconds of continuous track before a lock is achieved
local LOCK_LOSS_GRACE = 1.5 -- seconds out of track before the lock is lost

type Heli = {
	model: Model,
	health: number,
	maxHealth: number,
	pilot: Player?,
	passengers: { [Player]: boolean },
	flightState: string, -- "Grounded" | "Airborne" | "Falling" | "Destroyed"
	altitude: number,
	radarContacts: { { position: Vector3, faction: string } },
	lockTarget: Model?,
	lockProgress: number,
	lockState: string, -- "None" | "Tracking" | "Locked" | "Lost"
	lostSince: number?,
}

function HelicopterService:Init()
	self._helis = {} :: { [Model]: Heli }
	self._byPlayer = {} :: { [Player]: Model }
	self._accumulator = 0
	self._radarAccumulator = 0
end

-- --- registration -----------------------------------------------------------

function HelicopterService:register(model: Instance): Heli?
	if not model:IsA("Model") then
		return nil
	end
	local maxHealth = model:GetAttribute("MaxHealth") or 800
	local heli: Heli = {
		model = model,
		health = maxHealth,
		maxHealth = maxHealth,
		pilot = nil,
		passengers = {},
		flightState = "Grounded",
		altitude = 0,
		radarContacts = {},
		lockTarget = nil,
		lockProgress = 0,
		lockState = "None",
		lostSince = nil,
	}
	self._helis[model] = heli
	model:SetAttribute("HeliHealth", maxHealth)
	model:SetAttribute("FlightState", "Grounded")
	return heli
end

function HelicopterService:get(model: Model): Heli?
	return self._helis[model]
end

-- --- crew -------------------------------------------------------------------

function HelicopterService:enter(player: Player, model: Model, asPilot: boolean?): (boolean, string?)
	local heli = self._helis[model]
	if not heli then
		return false, "not a helicopter"
	end
	if heli.flightState == "Destroyed" then
		return false, "destroyed"
	end
	local players = Registry.expect("PlayerService")
	if not players:canFight(player) then
		return false, "unable"
	end
	if self._byPlayer[player] then
		return false, "already aboard"
	end

	local faction = model:GetAttribute("Faction")
	if type(faction) == "string" and faction ~= "" and players:getState(player).faction ~= faction then
		return false, "wrong faction"
	end

	if asPilot then
		if heli.pilot then
			return false, "pilot seat taken"
		end
		-- Piloting is rank-gated (and faction-gated via Data.Factions).
		local factions = Registry.expect("FactionService")
		if not factions:hasAbility(player, "Helicopter") then
			return false, "your faction has no air assets"
		end
		local permission = model:GetAttribute("RequiredPerm") or Data.Ranks.Permissions.PilotHelicopter
		local ranks = Registry.get("RankService")
		if ranks and not ranks:can(player, permission) then
			return false, "insufficient rank to pilot"
		end
		heli.pilot = player
	else
		heli.passengers[player] = true
	end

	self._byPlayer[player] = model
	self._stateEvent:FireAllClients(model, "Enter", player, asPilot == true)
	return true, nil
end

function HelicopterService:exit(player: Player): boolean
	local model = self._byPlayer[player]
	if not model then
		return false
	end
	local heli = self._helis[model]
	if heli then
		if heli.pilot == player then
			heli.pilot = nil
			-- Losing the pilot mid-air means the aircraft is going down.
			if heli.flightState == "Airborne" then
				self:_setFlightState(heli, "Falling")
			end
		end
		heli.passengers[player] = nil
	end
	self._byPlayer[player] = nil
	self._stateEvent:FireAllClients(model, "Exit", player, false)
	return true
end

-- --- flight state -----------------------------------------------------------

function HelicopterService:_setFlightState(heli: Heli, state: string)
	if heli.flightState == state then
		return
	end
	heli.flightState = state
	heli.model:SetAttribute("FlightState", state)
	self._stateEvent:FireAllClients(heli.model, "FlightState", nil, false, state)
end

function HelicopterService:_updateFlight(heli: Heli)
	local model = heli.model
	local primary = model.PrimaryPart
	if not primary then
		return
	end

	-- Altitude via a downward ray; ground distance is the useful number.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local hit = Workspace:Raycast(primary.Position, Vector3.new(0, -2000, 0), params)
	heli.altitude = hit and (primary.Position.Y - hit.Position.Y) or primary.Position.Y
	model:SetAttribute("Altitude", heli.altitude)

	if heli.flightState ~= "Destroyed" and heli.flightState ~= "Falling" then
		self:_setFlightState(heli, heli.altitude > 6 and "Airborne" or "Grounded")
	end

	-- Validate: an aircraft with no pilot should not be climbing.
	if not heli.pilot and heli.flightState == "Airborne" then
		local velocity = primary.AssemblyLinearVelocity
		if velocity.Y > 5 then
			self:_setFlightState(heli, "Falling")
		end
	end
end

-- --- radar + target tracking ------------------------------------------------

function HelicopterService:_updateRadar(heli: Heli)
	local primary = heli.model.PrimaryPart
	local pilot = heli.pilot
	if not primary or not pilot then
		heli.radarContacts = {}
		return
	end

	local players = Registry.expect("PlayerService")
	local factions = Registry.expect("FactionService")
	local origin = primary.Position
	local contacts = {}

	-- Radar sees vehicles/aircraft and players in the open within range. The
	-- SERVER decides what goes in this list, exactly like Eagle Eye.
	for _, other in Players:GetPlayers() do
		if other ~= pilot then
			local state = players:getState(other)
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and state.deployed and state.health ~= "Dead" then
				if factions:areEnemies(pilot, other) then
					local distance = (root.Position - origin).Magnitude
					if distance <= RADAR_RANGE then
						table.insert(contacts, { position = root.Position, faction = state.faction })
					end
				end
			end
		end
	end

	heli.radarContacts = contacts
	self._radarEvent:FireClient(pilot, contacts)
end

--[[
	Track a target the pilot is designating. Continuous track for LOCK_TIME
	achieves a lock; breaking track for LOCK_LOSS_GRACE loses it.
]]
function HelicopterService:track(player: Player, target: Model?)
	local model = self._byPlayer[player]
	local heli = model and self._helis[model]
	if not heli or heli.pilot ~= player then
		return
	end

	if target ~= heli.lockTarget then
		heli.lockTarget = target
		heli.lockProgress = 0
		heli.lostSince = nil
		self:_setLockState(heli, target and "Tracking" or "None")
	end
end

function HelicopterService:_setLockState(heli: Heli, state: string)
	if heli.lockState == state then
		return
	end
	heli.lockState = state
	heli.model:SetAttribute("LockState", state)
	if heli.pilot then
		self._lockEvent:FireClient(heli.pilot, state, heli.lockTarget)
	end
	-- A locked target is warned — being painted is information the victim earns.
	if state == "Locked" and heli.lockTarget then
		local victim = Players:GetPlayerFromCharacter(heli.lockTarget)
		if victim then
			self._lockEvent:FireClient(victim, "Painted", heli.model)
		end
	end
end

function HelicopterService:_updateLock(heli: Heli, dt: number)
	local target = heli.lockTarget
	if not target or not target.Parent then
		if heli.lockState ~= "None" then
			self:_setLockState(heli, "Lost")
			heli.lockTarget = nil
			heli.lockProgress = 0
		end
		return
	end

	local primary = heli.model.PrimaryPart
	local targetPart = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
	if not primary or not targetPart then
		return
	end

	-- Line of sight decides whether the track holds.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { heli.model, target }
	local direction = targetPart.Position - primary.Position
	local blocked = Workspace:Raycast(primary.Position, direction, params) ~= nil
	local inRange = direction.Magnitude <= RADAR_RANGE

	if not blocked and inRange then
		heli.lostSince = nil
		heli.lockProgress += dt
		if heli.lockProgress >= LOCK_TIME then
			self:_setLockState(heli, "Locked")
		else
			self:_setLockState(heli, "Tracking")
		end
	else
		heli.lostSince = heli.lostSince or os.clock()
		if os.clock() - (heli.lostSince :: number) >= LOCK_LOSS_GRACE then
			heli.lockTarget = nil
			heli.lockProgress = 0
			self:_setLockState(heli, "Lost")
		end
	end
end

-- --- damage -----------------------------------------------------------------

function HelicopterService:damage(model: Model, amount: number, attacker: Player?)
	local heli = self._helis[model]
	if not heli or amount <= 0 or heli.flightState == "Destroyed" then
		return
	end
	heli.health = math.max(0, heli.health - amount)
	model:SetAttribute("HeliHealth", heli.health)

	if heli.health <= 0 then
		self:_setFlightState(heli, "Destroyed")
		local damageService = Registry.get("DamageService")
		local ok, pivot = pcall(function()
			return model:GetPivot().Position
		end)
		if damageService and ok then
			damageService:applyRadial(pivot, 40, 250, attacker)
		end
		for passenger in heli.passengers do
			self:exit(passenger)
		end
		if heli.pilot then
			self:exit(heli.pilot)
		end
		self._stateEvent:FireAllClients(model, "Destroyed", attacker, false)
	elseif heli.health <= heli.maxHealth * 0.3 and heli.flightState == "Airborne" then
		self:_setFlightState(heli, "Falling")
	end
end

function HelicopterService:Start()
	self._stateEvent = Remotes.getEvent("Helicopter", "HeliState")
	self._radarEvent = Remotes.getEvent("Helicopter", "RadarUpdate")
	self._lockEvent = Remotes.getEvent("Helicopter", "LockState")

	for _, model in CollectionService:GetTagged(TAG) do
		self:register(model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(model)
		self:register(model)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model)
		if model:IsA("Model") then
			self._helis[model] = nil
		end
	end)

	Remotes.getEvent("Helicopter", "RequestEnter").OnServerEvent:Connect(function(player, model, asPilot)
		if typeof(model) == "Instance" and model:IsA("Model") then
			self:enter(player, model, asPilot == true)
		end
	end)
	Remotes.getEvent("Helicopter", "RequestExit").OnServerEvent:Connect(function(player)
		self:exit(player)
	end)
	Remotes.getEvent("Helicopter", "HeliInput").OnServerEvent:Connect(function(player, action, target)
		if action == "Track" then
			self:track(player, (typeof(target) == "Instance" and target:IsA("Model")) and target or nil)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:exit(player)
	end)

	RunService.Heartbeat:Connect(function(dt)
		self._accumulator += dt
		if self._accumulator < 0.2 then
			return
		end
		local step = self._accumulator
		self._accumulator = 0

		for model, heli in self._helis do
			if not model.Parent then
				self._helis[model] = nil
				continue
			end
			self:_updateFlight(heli)
			self:_updateLock(heli, step)
		end

		self._radarAccumulator += step
		if self._radarAccumulator >= RADAR_INTERVAL then
			self._radarAccumulator = 0
			for _, heli in self._helis do
				self:_updateRadar(heli)
			end
		end
	end)

	log.info(string.format("online — tag your aircraft '%s'; radar/lock state authoritative", TAG))
end

return HelicopterService
