--!strict
--[[
	MissionService (server-authoritative)
	-------------------------------------
	Missions are ordered/parallel groups of objectives. This service owns the
	authoritative mission state; ObjectiveService owns the individual holds.

	*** CREATES NO WORLD OBJECTS. *** Missions are DEFINED IN DATA and reference
	objective ids that your tagged world markers provide.

		Missions:define({
			id = "RECOVER_INTEL",
			faction = "Army",
			objectives = { "INTEL_ROOM", "EXTRACT_ALPHA" },
			ordered = true,        -- must be completed in sequence
			timeLimit = 900,       -- 0 = untimed
			startPermission = "StartMission",
		})

	Lifecycle: Inactive -> Active -> Complete | Failed. Starting and aborting
	are rank-gated through RankService, so mission control is an authority
	granted by rank rather than something any player can trigger.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)
local Data = require(Shared.Data)

local MissionService = {}
MissionService.Name = "MissionService"

local log = Logger.scope(MissionService.Name)

export type MissionDef = {
	id: string,
	displayName: string?,
	faction: string?,
	objectives: { string },
	ordered: boolean?,
	timeLimit: number?,
	startPermission: string?,
}

type Mission = {
	def: MissionDef,
	state: string, -- Inactive | Active | Complete | Failed
	completed: { [string]: boolean },
	startedAt: number?,
}

function MissionService:Init()
	self._config = Config.Mission
	self._missions = {} :: { [string]: Mission }
	self._accumulator = 0
end

-- --- definition -------------------------------------------------------------

function MissionService:define(def: MissionDef)
	self._missions[def.id] = {
		def = def,
		state = "Inactive",
		completed = {},
		startedAt = nil,
	}
	return self._missions[def.id]
end

function MissionService:get(id: string): Mission?
	return self._missions[id]
end

function MissionService:getState(id: string): string?
	local mission = self._missions[id]
	return mission and mission.state
end

function MissionService:_setState(id: string, state: string)
	local mission = self._missions[id]
	if not mission or mission.state == state then
		return
	end
	mission.state = state
	self._stateEvent:FireAllClients(id, state, self:progressOf(id))
	log.info(string.format("mission '%s' -> %s", id, state))
end

function MissionService:progressOf(id: string): number
	local mission = self._missions[id]
	if not mission then
		return 0
	end
	local total = #mission.def.objectives
	if total == 0 then
		return 0
	end
	local done = 0
	for _, objectiveId in mission.def.objectives do
		if mission.completed[objectiveId] then
			done += 1
		end
	end
	return done / total
end

-- The next objective that may be worked on (respects `ordered`).
function MissionService:activeObjectives(id: string): { string }
	local mission = self._missions[id]
	if not mission or mission.state ~= "Active" then
		return {}
	end
	if not mission.def.ordered then
		local open = {}
		for _, objectiveId in mission.def.objectives do
			if not mission.completed[objectiveId] then
				table.insert(open, objectiveId)
			end
		end
		return open
	end
	for _, objectiveId in mission.def.objectives do
		if not mission.completed[objectiveId] then
			return { objectiveId }
		end
	end
	return {}
end

-- --- control ----------------------------------------------------------------

function MissionService:start(id: string, initiator: Player?): (boolean, string?)
	local mission = self._missions[id]
	if not mission then
		return false, "no such mission"
	end
	if mission.state == "Active" then
		return false, "already active"
	end

	-- Starting a mission is an authority, not a free action.
	if initiator then
		local permission = mission.def.startPermission or Data.Ranks.Permissions.StartMission
		local ranks = Registry.get("RankService")
		if ranks and not ranks:can(initiator, permission) then
			return false, "insufficient rank"
		end
		if mission.def.faction then
			local players = Registry.expect("PlayerService")
			if players:getState(initiator).faction ~= mission.def.faction then
				return false, "wrong faction"
			end
		end
	end

	mission.completed = {}
	mission.startedAt = os.clock()
	self:_setState(id, "Active")

	-- Activate the objectives this mission owns.
	local objectives = Registry.get("ObjectiveService")
	if objectives then
		for _, objectiveId in self:activeObjectives(id) do
			objectives:setState(objectiveId, "Active")
		end
	end
	return true, nil
end

function MissionService:abort(id: string, initiator: Player?): (boolean, string?)
	local mission = self._missions[id]
	if not mission or mission.state ~= "Active" then
		return false, "not active"
	end
	if initiator then
		local ranks = Registry.get("RankService")
		if ranks and not ranks:can(initiator, Data.Ranks.Permissions.AbortMission) then
			return false, "insufficient rank"
		end
	end
	self:_setState(id, "Failed")
	return true, nil
end

-- Called by ObjectiveService when an objective completes.
function MissionService:onObjectiveComplete(objectiveId: string)
	for id, mission in self._missions do
		if mission.state == "Active" then
			for _, owned in mission.def.objectives do
				if owned == objectiveId then
					mission.completed[objectiveId] = true
					self._stateEvent:FireAllClients(id, mission.state, self:progressOf(id))

					if self:progressOf(id) >= 1 then
						self:_complete(id)
					else
						-- Open the next objective in an ordered mission.
						local objectives = Registry.get("ObjectiveService")
						if objectives then
							for _, nextId in self:activeObjectives(id) do
								objectives:setState(nextId, "Active")
							end
						end
					end
					break
				end
			end
		end
	end
end

function MissionService:_complete(id: string)
	local mission = self._missions[id]
	if not mission then
		return
	end
	self:_setState(id, "Complete")

	-- Reward the faction that ran it (progression only).
	local Players = game:GetService("Players")
	local players = Registry.expect("PlayerService")
	local ranks = Registry.get("RankService")
	local data = Registry.get("DataService")
	for _, player in Players:GetPlayers() do
		local state = players:getState(player)
		if state.deployed and (not mission.def.faction or state.faction == mission.def.faction) then
			if ranks then
				ranks:awardXp(player, 500)
			end
			if data then
				data:incrementStat(player, "missions")
			end
		end
	end
end

-- --- tick (time limits) -----------------------------------------------------

function MissionService:_tick()
	local now = os.clock()
	for id, mission in self._missions do
		if mission.state == "Active" and mission.def.timeLimit and mission.def.timeLimit > 0 then
			if mission.startedAt and now - mission.startedAt >= mission.def.timeLimit then
				self:_setState(id, "Failed")
			end
		end
	end
end

function MissionService:Start()
	self._stateEvent = Remotes.getEvent("Mission", "MissionState")

	RunService.Heartbeat:Connect(function(dt)
		self._accumulator += dt
		if self._accumulator < 1 then
			return
		end
		self._accumulator = 0
		self:_tick()
	end)

	log.info("online — mission framework (define missions over tagged objectives)")
end

return MissionService
