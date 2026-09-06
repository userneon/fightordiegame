--!strict
--[[
	InputController (client)
	------------------------
	Binds player input and translates it into server intent via Remotes.
	Keeps all keybinds in one place. Purely intent — the server decides outcomes.

	Bound now (Movement):
	  - Sprint: hold LeftShift (also gamepad ButtonL3) -> Movement.SetSprint(true/false)
	  - Crouch: toggle C   (also gamepad ButtonR3)     -> Movement.SetCrouch(true/false)

	More actions (revive, carry, enter vehicle, NVG…) get bound here as each
	system's client spec lands.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared.Modules.Logger)
local Remotes = require(Shared.Remotes)

local InputController = {}
InputController.Name = "InputController"

local log = Logger.scope(InputController.Name)

local ACTION_SPRINT = "FOD_Sprint"
local ACTION_CROUCH = "FOD_Crouch"

function InputController:Init()
	self._crouched = false
	self._setSprint = Remotes.getEvent("Movement", "SetSprint")
	self._setCrouch = Remotes.getEvent("Movement", "SetCrouch")
end

function InputController:Start()
	-- Sprint: fire on press/release so the server tracks a held state.
	ContextActionService:BindAction(ACTION_SPRINT, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			self._setSprint:FireServer(true)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			self._setSprint:FireServer(false)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)

	-- Crouch: toggle on press.
	ContextActionService:BindAction(ACTION_CROUCH, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			self._crouched = not self._crouched
			self._setCrouch:FireServer(self._crouched)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.C, Enum.KeyCode.ButtonR3)

	log.info("keybinds bound — Shift=sprint, C=crouch")
end

return InputController
