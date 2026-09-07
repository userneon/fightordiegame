--!strict
--[[
	CameraController (client)
	-------------------------
	Owns the GAMEPLAY camera policy and enforces that normal, on-foot play is
	FIRST-PERSON ONLY. It is mode-based so other camera contexts can be added
	later without entangling them:

	  - "Menu"      : hands off. The StartMenuController owns the menu camera; this
	                  controller does not touch it (so the menu is unchanged).
	  - "Gameplay"  : hard-locked first person — CameraMode.LockFirstPerson, zoom
	                  pinned, a watchdog that re-locks if anything flips it, plus
	                  first-person body awareness for visible weapon/hand/body/
	                  interaction animations.
	  - "Vehicle"   : seam for a future vehicle camera (stub).
	  - "Spectator" : seam for a future death / spectator camera (stub).

	Flow: the Start Menu's PLAY hands the camera back to the character and the
	server acks Remotes.Game.Deployed — that's the signal to enter Gameplay/FPP.
	Other systems drive the camera by calling CameraController:setMode(name).

	player.CameraMode persists across respawns, so FPP survives death without
	extra work; FirstPersonBody rebinds itself on CharacterAdded.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Remotes = require(Shared.Remotes)

local FirstPersonBody = require(script:WaitForChild("FirstPersonBody"))

local CameraController = {}
CameraController.Name = "CameraController"

local log = Logger.scope(CameraController.Name)

-- Roblox defaults, restored when we release the hard first-person lock.
local DEFAULT_MIN_ZOOM = 0.5
local DEFAULT_MAX_ZOOM = 128

function CameraController:Init()
	self._config = Config.Camera
	self._player = Players.LocalPlayer
	self._mode = nil :: string?
	self._bodyHandle = nil :: any
	self._camWatch = nil :: RBXScriptConnection?

	-- Mode registry. Each mode is { enter, exit }; setMode() runs exit on the old
	-- mode then enter on the new one. Add vehicle/spectator behaviour here later.
	self._modes = {
		Menu = {
			enter = function() end, -- hands off: StartMenuController owns this
			exit = function() end,
		},
		Gameplay = {
			enter = function()
				self:_enterGameplay()
			end,
			exit = function()
				self:_exitGameplay()
			end,
		},
		Vehicle = {
			enter = function()
				self:_enterVehicle()
			end,
			exit = function() end,
		},
		Spectator = {
			enter = function()
				self:_enterSpectator()
			end,
			exit = function() end,
		},
	}
end

-- --- public API ------------------------------------------------------------

-- Switch camera modes. Safe to call from other controllers/systems.
function CameraController:setMode(name: string)
	if self._mode == name then
		return
	end
	local current = self._mode and self._modes[self._mode]
	if current and current.exit then
		current.exit()
	end

	local target = self._modes[name]
	if not target then
		log.warn("unknown camera mode:", name)
		return
	end
	self._mode = name
	target.enter()
	log.info("mode ->", name)
end

function CameraController:getMode(): string?
	return self._mode
end

-- --- Gameplay (first-person only) ------------------------------------------

function CameraController:_enterGameplay()
	local player = self._player

	-- Hard lock: forces first person and disables zoom-out to third person.
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5

	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = self._config.GameplayFieldOfView
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			cam.CameraSubject = humanoid
		end
	end

	-- Watchdog: if anything tries to leave first person during gameplay, re-lock.
	self._camWatch = player:GetPropertyChangedSignal("CameraMode"):Connect(function()
		if self._mode == "Gameplay" and player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		end
	end)

	-- Body awareness so first-person animations are visible.
	if self._config.FirstPersonBody then
		self._bodyHandle = FirstPersonBody.start(player, self._config.HideHeadInFirstPerson)
	end
end

function CameraController:_exitGameplay()
	if self._camWatch then
		self._camWatch:Disconnect()
		self._camWatch = nil
	end
	if self._bodyHandle then
		self._bodyHandle.stop()
		self._bodyHandle = nil
	end
	-- Release the hard lock so vehicle/spectator modes can control freely.
	local player = self._player
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = DEFAULT_MIN_ZOOM
	player.CameraMaxZoomDistance = DEFAULT_MAX_ZOOM
end

-- --- future camera contexts (seams) ----------------------------------------

function CameraController:_enterVehicle()
	-- Placeholder: a vehicle camera (chase / cockpit) will live here and can
	-- reuse or bypass FPP as needed. Gameplay's exit() already released the lock.
	log.info("vehicle camera not implemented yet — using default")
end

function CameraController:_enterSpectator()
	-- Placeholder: death / spectator free-cam or target-follow will live here.
	log.info("spectator camera not implemented yet — using default")
end

-- --- lifecycle -------------------------------------------------------------

function CameraController:Start()
	-- Start hands-off; the Start Menu owns the camera until the player deploys.
	self:setMode("Menu")

	-- Fetch the deploy remote in a task so a not-yet-created remote can never
	-- block the client bootstrap (which would stop every later controller,
	-- including the Start Menu, from starting).
	task.spawn(function()
		local deployed = Remotes.getEvent("Game", "Deployed")
		deployed.OnClientEvent:Connect(function()
			self:setMode("Gameplay")
		end)
	end)

	-- If the player is already deployed when this runs (e.g. a rejoin or a future
	-- menu-less flow), enforce FPP immediately.
	if self._player:GetAttribute("Deployed") == true then
		self:setMode("Gameplay")
	end

	log.info("online — gameplay is first-person only")
end

return CameraController
