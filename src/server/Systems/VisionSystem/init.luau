--!strict
--[[
	VisionSystem (server-authoritative)
	-----------------------------------
	Owns: the authoritative power / blackout state and searchlights.

	Blackout and the power grid are shared world state, so the server owns them:
	it decides when power is on/off and broadcasts Remotes.Vision.BlackoutChanged.
	Searchlights you place in the world are driven by the server (sweep, target
	detection). NVG and personal flashlights are purely client-side *rendering*
	and live in the client NvgController — but their on/off may be reported here
	if gameplay (e.g. detection) depends on them.

	TODO (implement when the Blackout / Power / Searchlight spec is provided):
	  - Maintain power zones (by tag) and toggle Lighting/blackout ambient.
	  - Drive searchlight sweep + detection.
	  - Broadcast state to clients for local lighting response.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)

local VisionSystem = {}
VisionSystem.Name = "VisionSystem"

local log = Logger.scope(VisionSystem.Name)

function VisionSystem:Init()
	self._config = Config.Vision
end

function VisionSystem:Start()
	log.info("ready (stub — awaiting Blackout/Power/Searchlight spec)")
end

return VisionSystem
