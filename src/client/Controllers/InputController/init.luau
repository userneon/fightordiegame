--!strict
--[[
	InputController (client)
	------------------------
	Central place to bind player input (ContextActionService / UserInputService)
	and translate it into server intent via Remotes. Keeps keybinds in one place.

	Examples of what will live here once specs arrive:
	  - Sprint hold      -> Remotes.Movement.SetSprint
	  - Revive interact  -> Remotes.Medic.RequestRevive
	  - Carry / drop     -> Remotes.Carry.RequestCarry / RequestDrop
	  - Enter vehicle    -> Remotes.Vehicle.RequestEnter
	  - Toggle NVG       -> handled locally + NvgController

	TODO: bind actions as each system's client spec is defined.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared.Modules.Logger)

local InputController = {}
InputController.Name = "InputController"

local log = Logger.scope(InputController.Name)

function InputController:Init() end

function InputController:Start()
	log.info("ready (stub — no keybinds bound yet)")
end

return InputController
