--!strict
--[[
	ObjectiveService (server-authoritative)
	---------------------------------------
	Individual objectives — the units a mission is built from.

	*** CREATES NO WORLD OBJECTS. *** You place and tag the markers; this
	service gives them behaviour and holds the authoritative state.

	Connect a world object
	----------------------
	  Tag an Instance "Objective" and give it attributes:
	    ObjectiveId    unique string
	    ObjectiveKind  "Hold" | "Capture" | "Extract"     (default "Hold")
	    HoldTime       seconds required (e.g. 300 for 5 minutes)
	    Faction        which side may progress it          [optional]
	    Radius         studs a player must stay within     [optional]

	Hold semantics (per spec): hold E for the duration; movement outside the
	radius or releasing resets progress to zero. Progress is stored on the
	OBJECTIVE, not the player, so a squad can take turns only if you allow it
	(SharedProgress attribute) — otherwise each player's progress is their own.
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

local ObjectiveService = {}
ObjectiveService.Name = "ObjectiveService"

local log = Logger.scope(ObjectiveService.Name)

local TAG = "Objective"

type Objective = {
	id: string,
	kind: string,
	object: Instance,
	state: string, -- Inactive | Active | InProgress | Complete | Failed
	duration: number,
	radius: number,
	faction: string?,
	shared: boolean,
	progress: number,
	holders: { [Player]: Vector3 }, -- player -> position when they began
}

function ObjectiveService:Init()
	self._config = Config.Mission
	self._objectives = {} :: { [string]: Objective }
	self._accumulator = 0
end

-- --- registration -----------------------------------------------------------

function ObjectiveService:register(object: Instance): Objective?
	local id = object:GetAttribute("ObjectiveId")
	if type(id) ~= "string" or id == "" then
		log.warn(string.format("'%s' tagged %s but has no ObjectiveId", object.Name, TAG))
		return nil
	end

	local objective: Objective = {
		id = id,
		kind = object:GetAttribute("ObjectiveKind") or "Hold",
		object = object,
		state = "Active",
		duration = object:GetAttribute("HoldTime") or self._config.DefaultHoldTime,
		radius = object:GetAttribute("Radius") or self._config.HoldMoveTolerance * 3,
		faction = object:GetAttribute("Faction"),
		shared = object:GetAttribute("SharedProgress") == true,
		progress = 0,
		holders = {},
	}
	self._objectives[id] = objective
	object:SetAttribute("ObjectiveState", objective.state)
	object:SetAttribute("ObjectiveProgress", 0)
	return objective
end

function ObjectiveService:get(id: string): Objective?
	return self._objectives[id]
end

function ObjectiveService:setState(id: string, state: string)
	local objective = self._objectives[id]
	if not objective or objective.state == state then
		return
	end
	objective.state = state
	objective.object:SetAttribute("ObjectiveState", state)
	self._stateEvent:FireAllClients(id, state, objective.progress)
	log.info(string.format("objective '%s' -> %s", id, state))
end

-- --- holding ----------------------------------------------------------------

local function positionOf(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return (root and root:IsA("BasePart")) and root.Position or nil
end

local function objectPosition(object: Instance): Vector3?
	if object:IsA("BasePart") then
		return object.Position
	end
	if object:IsA("Model") then
		local part = object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart", true)
		return part and part.Position or nil
	end
	local part = object:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

function ObjectiveService:canHold(player: Player, objective: Objective): (boolean, string?)
	if objective.state ~= "Active" and objective.state ~= "InProgress" then
		return false, "objective not active"
	end
	local players = Registry.expect("PlayerService")
	if not players:canFight(player) then
		return false, "unable"
	end
	if objective.faction and players:getState(player).faction ~= objective.faction then
		return false, "wrong faction"
	end
	local playerPosition = positionOf(player)
	local target = objectPosition(objective.object)
	if not playerPosition or not target then
		return false, "no position"
	end
	if (playerPosition - target).Magnitude > objective.radius then
		return false, "out of range"
	end
	return true, nil
end

function ObjectiveService:beginHold(player: Player, id: string)
	local objective = self._objectives[id]
	if not objective then
		return
	end
	local ok = self:canHold(player, objective)
	if not ok then
		return
	end
	local position = positionOf(player)
	if position then
		objective.holders[player] = position
		self:setState(id, "InProgress")
	end
end

function ObjectiveService:releaseHold(player: Player, id: string)
	local objective = self._objectives[id]
	if not objective then
		return
	end
	objective.holders[player] = nil
	-- Per spec: interruption RESETS progress rather than pausing it.
	if not objective.shared then
		objective.progress = 0
		objective.object:SetAttribute("ObjectiveProgress", 0)
	end
	if next(objective.holders) == nil then
		if not objective.shared then
			objective.progress = 0
		end
		if objective.state == "InProgress" then
			self:setState(id, "Active")
		end
	end
end

-- --- tick -------------------------------------------------------------------

function ObjectiveService:_tick(dt: number)
	for id, objective in self._objectives do
		if objective.state == "InProgress" then
			local anyHolding = false

			for player, startPosition in objective.holders do
				local valid = select(1, self:canHold(player, objective))
				local current = positionOf(player)
				-- Movement beyond tolerance resets, exactly like a medic hold.
				if valid and current and (current - startPosition).Magnitude <= self._config.HoldMoveTolerance then
					anyHolding = true
				else
					self:releaseHold(player, id)
				end
			end

			if anyHolding then
				objective.progress = math.clamp(objective.progress + dt / math.max(0.01, objective.duration), 0, 1)
				objective.object:SetAttribute("ObjectiveProgress", objective.progress)
				self._progressEvent:FireAllClients(id, objective.progress)

				if objective.progress >= 1 then
					self:setState(id, "Complete")
					objective.holders = {}
					-- Tell the mission layer; it decides what completion means.
					local missions = Registry.get("MissionService")
					if missions then
						missions:onObjectiveComplete(id)
					end
				end
			end
		end
	end
end

function ObjectiveService:Start()
	self._stateEvent = Remotes.getEvent("Mission", "ObjectiveState")
	self._progressEvent = Remotes.getEvent("Objective", "ObjectiveProgress")

	for _, object in CollectionService:GetTagged(TAG) do
		self:register(object)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(object)
		self:register(object)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(object)
		local id = object:GetAttribute("ObjectiveId")
		if type(id) == "string" then
			self._objectives[id] = nil
		end
	end)

	Remotes.getEvent("Objective", "RequestHold").OnServerEvent:Connect(function(player, id)
		if type(id) == "string" then
			self:beginHold(player, id)
		end
	end)
	Remotes.getEvent("Objective", "ReleaseHold").OnServerEvent:Connect(function(player, id)
		if type(id) == "string" then
			self:releaseHold(player, id)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for id in self._objectives do
			self:releaseHold(player, id)
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		self._accumulator += dt
		if self._accumulator < self._config.HoldTickInterval then
			return
		end
		local step = self._accumulator
		self._accumulator = 0
		self:_tick(step)
	end)

	log.info(string.format("online — tag world markers '%s' to connect them", TAG))
end

return ObjectiveService
