--!strict
--[[
	SpawnService (server-authoritative)
	-----------------------------------
	Places players into the world and owns respawn timing.

	IMPORTANT: this service creates NO map geometry. It locates the spawn zones
	YOU build in Studio by CollectionService tag (Data.Factions[x].spawnTag,
	e.g. "ArmySpawn" / "TerroristSpawn") and teleports characters onto them. If
	a faction has no tagged zone it falls back to any SpawnLocation, then to the
	world origin — so the game still runs before your map exists.

	Respawn timing (per spec):
	  Army      — standard soldier time; MEDICS wait longer (role multiplier).
	  Terrorist — faster per game rules.
	Both come from data: Factions[faction].respawnTime * Roles[role].multiplier.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)
local Data = require(Shared.Data)

local SpawnService = {}
SpawnService.Name = "SpawnService"

local log = Logger.scope(SpawnService.Name)

local SPAWN_HEIGHT = 4 -- studs above the pad so nobody spawns inside it

function SpawnService:Init()
	self._pending = {} :: { [Player]: boolean } -- respawn timers in flight
end

-- --- spawn point resolution -------------------------------------------------

function SpawnService:_zonesFor(faction: string): { BasePart }
	local def = Data.Factions.get(faction)
	local zones: { BasePart } = {}
	if def then
		for _, inst in CollectionService:GetTagged(def.spawnTag) do
			if inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) then
				table.insert(zones, inst)
			end
		end
	end
	return zones
end

-- Fallback chain so the game is playable before the map is tagged.
function SpawnService:_fallbackZones(): { BasePart }
	local zones: { BasePart } = {}
	for _, inst in Workspace:GetDescendants() do
		if inst:IsA("SpawnLocation") then
			table.insert(zones, inst)
		end
	end
	return zones
end

-- Prefer a zone with no enemy standing near it, so players don't spawn into a
-- muzzle. Falls back to a random zone when every zone is contested.
function SpawnService:_pickZone(player: Player, faction: string): BasePart?
	local zones = self:_zonesFor(faction)
	if #zones == 0 then
		zones = self:_fallbackZones()
	end
	if #zones == 0 then
		return nil
	end

	local factions = Registry.get("FactionService")
	local safe: { BasePart } = {}
	for _, zone in zones do
		local contested = false
		if factions then
			for _, other in Players:GetPlayers() do
				if other ~= player then
					local char = other.Character
					local root = char and char:FindFirstChild("HumanoidRootPart")
					if root and root:IsA("BasePart") then
						if factions:areEnemies(player, other) then
							if (root.Position - zone.Position).Magnitude < 60 then
								contested = true
								break
							end
						end
					end
				end
			end
		end
		if not contested then
			table.insert(safe, zone)
		end
	end

	local pool = #safe > 0 and safe or zones
	return pool[math.random(1, #pool)]
end

function SpawnService:getSpawnCFrame(player: Player, faction: string): CFrame
	local zone = self:_pickZone(player, faction)
	if not zone then
		return CFrame.new(0, SPAWN_HEIGHT, 0)
	end
	-- Random offset inside the pad so a squad doesn't stack on one point.
	local halfX = math.max(0, zone.Size.X / 2 - 1)
	local halfZ = math.max(0, zone.Size.Z / 2 - 1)
	local offset = Vector3.new(
		math.random(-halfX * 100, halfX * 100) / 100,
		zone.Size.Y / 2 + SPAWN_HEIGHT,
		math.random(-halfZ * 100, halfZ * 100) / 100
	)
	return CFrame.new(zone.Position + offset) * CFrame.Angles(0, zone.Orientation.Y * math.pi / 180, 0)
end

-- --- spawning ---------------------------------------------------------------

-- Load the character and place it at a faction spawn. Returns success.
function SpawnService:spawnPlayer(player: Player): boolean
	local players = Registry.expect("PlayerService")
	local state = players:getState(player)

	local faction = state.faction
	if not Data.Factions.isPlayable(faction) then
		local factions = Registry.get("FactionService")
		faction = factions and factions:autoAssign(player) or "Army"
	end

	player:LoadCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and root:IsA("BasePart") then
		root.CFrame = self:getSpawnCFrame(player, faction)
	end

	if self._respawned then
		self._respawned:FireClient(player, faction)
	end
	return true
end

-- Seconds this player must wait before returning to the fight.
function SpawnService:getRespawnTime(player: Player): number
	local players = Registry.expect("PlayerService")
	local state = players:getState(player)
	local factionDef = Data.Factions.get(state.faction)
	local roleDef = Data.Roles.get(state.role)
	local base = factionDef and factionDef.respawnTime or 10
	return base * roleDef.respawnMultiplier
end

-- Schedule a respawn. Undeployed players are never respawned (they belong in
-- the Start Menu until they press PLAY).
function SpawnService:scheduleRespawn(player: Player)
	if self._pending[player] then
		return
	end
	local players = Registry.expect("PlayerService")
	if not players:getState(player).deployed then
		return
	end

	self._pending[player] = true
	local wait = self:getRespawnTime(player)
	task.spawn(function()
		task.wait(wait)
		self._pending[player] = nil
		-- Re-check: they may have left or undeployed while the timer ran.
		if player.Parent and players:getState(player).deployed then
			self:spawnPlayer(player)
		end
	end)
end

function SpawnService:Start()
	self._respawned = Remotes.getEvent("Spawn", "Respawned")

	-- Manual respawn request (e.g. "give up" while bleeding out).
	local requestRespawn = Remotes.getEvent("Spawn", "RequestRespawn")
	requestRespawn.OnServerEvent:Connect(function(player)
		local players = Registry.expect("PlayerService")
		local state = players:getState(player)
		-- Only from a downed or dead state — never a free teleport while alive.
		if state.health == "Alive" or not state.deployed then
			return
		end
		if state.health ~= "Dead" then
			players:kill(player, state.lastDamageBy)
		end
		self:scheduleRespawn(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._pending[player] = nil
	end)

	log.info("online — faction spawn zones by tag, role-scaled respawn")
end

return SpawnService
