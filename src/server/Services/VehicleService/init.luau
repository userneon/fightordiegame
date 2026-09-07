--!strict
--[[
	VehicleService (server-authoritative)
	-------------------------------------
	Vehicle framework. *** CREATES NO VEHICLE MODELS. *** You build and tag the
	vehicles; this service owns ownership, occupancy and damage state.

	Connect a vehicle you built
	---------------------------
	  Tag the vehicle Model "Vehicle" and optionally set attributes:
	    VehicleType    free-form string ("Truck", "APC", …)
	    MaxHealth      default Config-driven
	    RequiredPerm   RankService permission to DRIVE (e.g. DriveArmor)
	    Faction        restrict use to one side           [optional]
	  Seats are ordinary Roblox VehicleSeat/Seat instances inside the model;
	  the first VehicleSeat is treated as the driver's.

	Owns: ownership (network + claim), enter/exit validation, seat validation,
	driver/passenger state, vehicle damage, tire damage, crash damage and
	passenger injury calculation.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)

local VehicleService = {}
VehicleService.Name = "VehicleService"

local log = Logger.scope(VehicleService.Name)

local TAG = "Vehicle"
local CRASH_SPEED_THRESHOLD = 55 -- studs/s of sudden loss before damage
local CRASH_DAMAGE_SCALE = 1.6

type VehicleRecord = {
	model: Model,
	vehicleType: string,
	health: number,
	maxHealth: number,
	owner: Player?,
	driver: Player?,
	passengers: { [Player]: boolean },
	tires: { [BasePart]: number },
	lastVelocity: Vector3,
	engineDead: boolean,
}

function VehicleService:Init()
	self._config = Config.Vehicle
	self._vehicles = {} :: { [Model]: VehicleRecord }
	self._byPlayer = {} :: { [Player]: Model }
	self._accumulator = 0
end

-- --- registration -----------------------------------------------------------

function VehicleService:register(model: Instance): VehicleRecord?
	if not model:IsA("Model") then
		return nil
	end
	local maxHealth = model:GetAttribute("MaxHealth") or 1000
	local record: VehicleRecord = {
		model = model,
		vehicleType = model:GetAttribute("VehicleType") or "Vehicle",
		health = maxHealth,
		maxHealth = maxHealth,
		owner = nil,
		driver = nil,
		passengers = {},
		tires = {},
		lastVelocity = Vector3.zero,
		engineDead = false,
	}

	-- Any part tagged/named as a tire gets its own damage pool.
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and (part.Name == "Tire" or CollectionService:HasTag(part, "Tire")) then
			record.tires[part] = 100
		end
	end

	self._vehicles[model] = record
	model:SetAttribute("VehicleHealth", record.health)
	return record
end

function VehicleService:get(model: Model): VehicleRecord?
	return self._vehicles[model]
end

function VehicleService:getVehicleOf(player: Player): Model?
	return self._byPlayer[player]
end

-- --- seat helpers -----------------------------------------------------------

local function seatsOf(model: Model): { Seat | VehicleSeat }
	local seats = {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("VehicleSeat") or inst:IsA("Seat") then
			table.insert(seats, inst)
		end
	end
	return seats
end

local function freeSeat(model: Model, driverOnly: boolean?): (Seat | VehicleSeat)?
	for _, seat in seatsOf(model) do
		local isDriver = seat:IsA("VehicleSeat")
		if (driverOnly == nil or isDriver == driverOnly) and seat.Occupant == nil then
			return seat
		end
	end
	return nil
end

-- --- enter / exit -----------------------------------------------------------

function VehicleService:canEnter(player: Player, model: Model): (boolean, string?)
	local record = self._vehicles[model]
	if not record then
		return false, "not a vehicle"
	end
	local players = Registry.expect("PlayerService")
	if not players:canFight(player) then
		return false, "unable"
	end
	if self._byPlayer[player] then
		return false, "already in a vehicle"
	end

	-- Faction restriction, if the builder set one.
	local faction = model:GetAttribute("Faction")
	if type(faction) == "string" and faction ~= "" then
		if players:getState(player).faction ~= faction then
			return false, "wrong faction"
		end
	end

	-- Proximity.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local pivotOk, pivot = pcall(function()
		return model:GetPivot().Position
	end)
	if root and root:IsA("BasePart") and pivotOk then
		if (root.Position - pivot).Magnitude > 25 then
			return false, "too far"
		end
	end
	return true, nil
end

function VehicleService:enter(player: Player, model: Model, asDriver: boolean?): (boolean, string?)
	local ok, reason = self:canEnter(player, model)
	if not ok then
		return false, reason
	end
	local record = self._vehicles[model]

	-- Driving may be rank-gated (e.g. armour requires DriveArmor).
	if asDriver then
		local permission = model:GetAttribute("RequiredPerm")
		if type(permission) == "string" and permission ~= "" then
			local ranks = Registry.get("RankService")
			if ranks and not ranks:can(player, permission) then
				return false, "insufficient rank to drive"
			end
		end
		if record.engineDead then
			return false, "engine is dead"
		end
	end

	local seat = freeSeat(model, asDriver)
	if not seat then
		return false, "no free seat"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "no character"
	end

	seat:Sit(humanoid)
	self._byPlayer[player] = model

	if seat:IsA("VehicleSeat") then
		record.driver = player
		record.owner = record.owner or player
		-- Network ownership to the driver for responsive physics.
		if self._config.NetworkOwnershipToDriver then
			pcall(function()
				local primary = model.PrimaryPart or seat
				primary:SetNetworkOwner(player)
			end)
		end
	else
		record.passengers[player] = true
	end

	self._stateEvent:FireAllClients(model, "Enter", player, seat:IsA("VehicleSeat"))
	return true, nil
end

function VehicleService:exit(player: Player): boolean
	local model = self._byPlayer[player]
	if not model then
		return false
	end
	local record = self._vehicles[model]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart then
		humanoid.Sit = false
	end

	if record then
		if record.driver == player then
			record.driver = nil
			pcall(function()
				local primary = model.PrimaryPart
				if primary then
					primary:SetNetworkOwnershipAuto()
				end
			end)
		end
		record.passengers[player] = nil
	end
	self._byPlayer[player] = nil
	self._stateEvent:FireAllClients(model, "Exit", player, false)
	return true
end

-- --- damage -----------------------------------------------------------------

function VehicleService:damage(model: Model, amount: number, attacker: Player?)
	local record = self._vehicles[model]
	if not record or amount <= 0 then
		return
	end
	record.health = math.max(0, record.health - amount)
	model:SetAttribute("VehicleHealth", record.health)

	-- Engine fails below the configured fraction; the vehicle becomes a wreck.
	if not record.engineDead and record.health <= record.maxHealth * self._config.EngineDamageThreshold then
		record.engineDead = true
		model:SetAttribute("EngineDead", true)
		self._stateEvent:FireAllClients(model, "EngineDead", nil, false)
	end

	if record.health <= 0 then
		self:_destroy(model, attacker)
	end
end

function VehicleService:damageTire(tire: BasePart, amount: number)
	for _, record in self._vehicles do
		local current = record.tires[tire]
		if current then
			local remaining = math.max(0, current - amount)
			record.tires[tire] = remaining
			tire:SetAttribute("TireHealth", remaining)
			if remaining <= 0 then
				tire:SetAttribute("TireBlown", true)
				self._stateEvent:FireAllClients(record.model, "TireBlown", nil, false)
			end
			return
		end
	end
end

-- Occupants take injury proportional to the impact; the driver takes more.
function VehicleService:_applyCrashInjury(record: VehicleRecord, severity: number)
	local damageService = Registry.get("DamageService")
	if not damageService then
		return
	end
	local function hurt(player: Player, scale: number)
		damageService:applyDamage(player, {
			amount = severity * scale,
			zone = "Chest",
			attacker = nil,
			ignoreArmor = false,
		})
	end
	if record.driver then
		hurt(record.driver, 1.0)
	end
	for passenger in record.passengers do
		hurt(passenger, 0.7)
	end
end

function VehicleService:_destroy(model: Model, attacker: Player?)
	local record = self._vehicles[model]
	if not record then
		return
	end
	-- Everyone aboard is caught in it.
	local damageService = Registry.get("DamageService")
	if damageService then
		local ok, pivot = pcall(function()
			return model:GetPivot().Position
		end)
		if ok then
			damageService:applyRadial(pivot, 25, 150, attacker)
		end
	end
	for passenger in record.passengers do
		self:exit(passenger)
	end
	if record.driver then
		self:exit(record.driver)
	end
	self._stateEvent:FireAllClients(model, "Destroyed", attacker, false)
	model:SetAttribute("Destroyed", true)
end

-- --- crash detection --------------------------------------------------------

function VehicleService:_tick()
	for model, record in self._vehicles do
		if not model.Parent then
			self._vehicles[model] = nil
			continue
		end
		local primary = model.PrimaryPart
		if primary then
			local velocity = primary.AssemblyLinearVelocity
			local delta = (velocity - record.lastVelocity).Magnitude
			record.lastVelocity = velocity
			-- A sudden large velocity change is an impact.
			if delta > CRASH_SPEED_THRESHOLD then
				local severity = (delta - CRASH_SPEED_THRESHOLD) * CRASH_DAMAGE_SCALE
				self:damage(model, severity)
				self:_applyCrashInjury(record, severity * 0.35)
			end
		end
	end
end

function VehicleService:Start()
	self._stateEvent = Remotes.getEvent("Vehicle", "VehicleState")

	for _, model in CollectionService:GetTagged(TAG) do
		self:register(model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(model)
		self:register(model)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model)
		if model:IsA("Model") then
			self._vehicles[model] = nil
		end
	end)

	Remotes.getEvent("Vehicle", "RequestEnter").OnServerEvent:Connect(function(player, model, asDriver)
		if typeof(model) == "Instance" and model:IsA("Model") then
			self:enter(player, model, asDriver == true)
		end
	end)
	Remotes.getEvent("Vehicle", "RequestExit").OnServerEvent:Connect(function(player)
		self:exit(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:exit(player)
	end)

	RunService.Heartbeat:Connect(function(dt)
		self._accumulator += dt
		if self._accumulator < 0.2 then
			return
		end
		self._accumulator = 0
		self:_tick()
	end)

	log.info(string.format("online — tag your vehicles '%s' to connect them", TAG))
end

return VehicleService
