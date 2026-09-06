--!strict
--[[
	Client bootstrap — FIGHT OR DIE (NOMAD BROS)
	--------------------------------------------
	Single entry point for all client-side (per-player) logic: input, HUD/UI,
	local visual effects (NVG, flashlight), camera. The client never decides
	gameplay outcomes — it sends intent to the server via Remotes and renders
	the authoritative results.

	Mirrors the server: discovers Controllers/, then Init() all, Start() all.
	Add a controller by dropping a folder in Controllers/.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared.Modules.Logger)

local log = Logger.scope("Client")

local controllersFolder = script:WaitForChild("Controllers")
local controllers: { any } = {}

for _, child in controllersFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if ok and type(result) == "table" then
			table.insert(controllers, result)
		else
			log.error(string.format("failed to require controller '%s': %s", child.Name, tostring(result)))
		end
	end
end

for _, controller in controllers do
	if type(controller.Init) == "function" then
		local ok, err = pcall(controller.Init, controller)
		if not ok then
			log.error(string.format("Init failed for '%s': %s", tostring(controller.Name), tostring(err)))
		end
	end
end

for _, controller in controllers do
	if type(controller.Start) == "function" then
		local ok, err = pcall(controller.Start, controller)
		if not ok then
			log.error(string.format("Start failed for '%s': %s", tostring(controller.Name), tostring(err)))
		end
	end
end

log.info(string.format("bootstrap complete — %d controller(s) online", #controllers))
