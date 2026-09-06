--!strict
--[[
	NvgController (client)
	----------------------
	Owns the LOCAL visual rendering of night-vision goggles and the personal
	flashlight — these are per-player camera/lighting effects, so they belong on
	the client for responsiveness and to avoid replicating heavy lighting.

	Coordinates with the server VisionSystem only where gameplay depends on it
	(e.g. reacting to Remotes.Vision.BlackoutChanged, or reporting NVG on/off if
	detection uses it).

	TODO (implement when the NVG / Flashlight spec is provided):
	  - Toggle NVG post-effect (ColorCorrection/tint, brightness) on keybind.
	  - Spawn/aim a SpotLight flashlight from the character/weapon.
	  - Respond to blackout by adjusting local lighting.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)

local NvgController = {}
NvgController.Name = "NvgController"

local log = Logger.scope(NvgController.Name)

function NvgController:Init()
	self._config = Config.Vision
end

function NvgController:Start()
	log.info("ready (stub — awaiting NVG/Flashlight spec)")
end

return NvgController
