--!strict
--[[
	SpawnSystem (server-authoritative)
	----------------------------------
	Owns: spawning and respawning players at team spawn zones.

	IMPORTANT: This system does NOT create map geometry. It locates the spawn
	zones YOU build in the world by CollectionService tag
	(Config.Spawn.ArmySpawnTag / TerroristSpawnTag) and teleports characters
	there. Tag your spawn parts in Studio and this system finds them — the world
	stays entirely your work.

	TODO (implement when the Spawn/Respawn spec is provided):
	  - Resolve tagged spawn zones per team; pick a safe/free spawn point.
	  - Handle death -> Config.Spawn.RespawnTime -> Remotes.Spawn.Respawned.
	  - Coordinate with WoundedSystem (don't respawn the merely wounded).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)

local SpawnSystem = {}
SpawnSystem.Name = "SpawnSystem"

local log = Logger.scope(SpawnSystem.Name)

function SpawnSystem:Init()
	self._config = Config.Spawn
end

function SpawnSystem:Start()
	log.info("ready (stub — awaiting Spawn/Respawn spec; looks for tagged spawn zones in your map)")
end

return SpawnSystem
