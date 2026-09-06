--!strict
--[[
	HUDController (client)
	----------------------
	Owns the player-facing HUD/UI: health & wounded/bleed-out indicator,
	inventory + weight readout, interaction prompts (revive, carry, search
	corpse, enter vehicle), medic treatment progress bar, drone/vehicle overlays.

	Purely presentational — it reflects authoritative state pushed from the
	server over Remotes; it never decides outcomes.

	TODO: build UI + bind to remote events as each system's spec arrives.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared.Modules.Logger)

local HUDController = {}
HUDController.Name = "HUDController"

local log = Logger.scope(HUDController.Name)

function HUDController:Init() end

function HUDController:Start()
	log.info("ready (stub — no HUD built yet)")
end

return HUDController
