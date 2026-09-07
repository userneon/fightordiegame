--!strict
--[[
	ServerBootstrap — FIGHT OR DIE (NOMAD BROS)
	-------------------------------------------
	Single entry point for all server-authoritative gameplay.

	Responsibilities:
	  1. Build every declared remote so clients can safely WaitForChild them.
	  2. Discover every Service under Services/ (a folder with an init.luau
	     returning { Name, Init?, Start? }).
	  3. Register each service in the shared Registry BEFORE any Init runs, so
	     services can resolve each other by name without import cycles.
	  4. Run the two-phase lifecycle: Init() on all, then Start() on all.

	Add a service by dropping a folder in Services/. No edits here required.
	Modules whose name begins with "_" are treated as private helpers and are
	not given a lifecycle.

	This bootstrap owns NO gameplay logic and never touches map geometry — the
	world is authored separately in Studio.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)

local log = Logger.scope("Server")

-- 1. Create remotes up front.
Remotes.build()

-- 2. Load services.
local servicesFolder = script:WaitForChild("Services")
local services: { any } = {}

for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") and string.sub(child.Name, 1, 1) ~= "_" then
		local ok, result = pcall(require, child)
		if ok and type(result) == "table" then
			table.insert(services, result)
			-- 3. Register before Init so cross-service lookups always resolve.
			Registry.register(result.Name or child.Name, result)
		else
			log.error(string.format("failed to require service '%s': %s", child.Name, tostring(result)))
		end
	end
end

-- 4a. Init phase.
for _, service in services do
	if type(service.Init) == "function" then
		local ok, err = pcall(service.Init, service)
		if not ok then
			log.error(string.format("Init failed for '%s': %s", tostring(service.Name), tostring(err)))
		end
	end
end

-- 4b. Start phase.
for _, service in services do
	if type(service.Start) == "function" then
		local ok, err = pcall(service.Start, service)
		if not ok then
			log.error(string.format("Start failed for '%s': %s", tostring(service.Name), tostring(err)))
		end
	end
end

log.info(string.format("bootstrap complete — %d service(s) online", #services))
