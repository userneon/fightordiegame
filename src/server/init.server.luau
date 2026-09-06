--!strict
--[[
	Server bootstrap — FIGHT OR DIE (NOMAD BROS)
	--------------------------------------------
	Single entry point for all server-authoritative gameplay.

	Responsibilities:
	  1. Build every declared remote so clients can safely WaitForChild them.
	  2. Discover every System module under Systems/ (each is a folder with an
	     init.luau returning a System table).
	  3. Run the two-phase lifecycle: Init() on all, then Start() on all.
	     Two phases let systems reference each other safely — all are
	     constructed before any begins running.

	Add a new system by dropping a folder in Systems/. No edits here required.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Logger = require(Shared.Modules.Logger)

local log = Logger.scope("Server")

-- 1. Create remotes up front.
Remotes.build()

-- 2. Load systems.
local systemsFolder = script:WaitForChild("Systems")
local systems: { any } = {}

for _, child in systemsFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if ok and type(result) == "table" then
			table.insert(systems, result)
		else
			log.error(string.format("failed to require system '%s': %s", child.Name, tostring(result)))
		end
	end
end

-- 3a. Init phase.
for _, system in systems do
	if type(system.Init) == "function" then
		local ok, err = pcall(system.Init, system)
		if not ok then
			log.error(string.format("Init failed for '%s': %s", tostring(system.Name), tostring(err)))
		end
	end
end

-- 3b. Start phase.
for _, system in systems do
	if type(system.Start) == "function" then
		local ok, err = pcall(system.Start, system)
		if not ok then
			log.error(string.format("Start failed for '%s': %s", tostring(system.Name), tostring(err)))
		end
	end
end

log.info(string.format("bootstrap complete — %d system(s) online", #systems))
