--!strict
--[[
	MovementService (server-authoritative)
	--------------------------------------
	Owns the character movement model:
	  - Walk / Sprint / Crouch speeds and jump tuning
	  - Stamina (sprinting drains it, it regenerates when you stop)
	  - Heavy Walk state driven by carried weight
	  - Inventory weight -> speed penalty (reads InventoryService)
	  - Downed players are immobilised (PlayerService is the authority on that)

	Authority model: the character's own client simulates physics, but Humanoid
	properties set on the SERVER replicate down and are the shared truth. So the
	server owns WalkSpeed/JumpPower; clients only send intent (sprint/crouch)
	over Remotes.Movement. AntiCheatService does the speed sanity checks.

	Replicated as Player attributes:
	  Stamina, MaxStamina, Sprinting, Crouching, HeavyWalk, CarriedWeight

	Other services can call setSpeedMultiplier(player, m) for temporary effects
	(carrying a casualty, injuries) without fighting this loop over WalkSpeed.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)

local MovementService = {}
MovementService.Name = "MovementService"

local log = Logger.scope(MovementService.Name)

type MoveState = {
	wantSprint: boolean,
	crouching: boolean,
	sprinting: boolean,
	stamina: number,
	lastSprintEnd: number,
	speedMultiplier: number,
	humanoid: Humanoid?,
}

function MovementService:Init()
	self._config = Config.Movement
	self._states = {} :: { [Player]: MoveState }
	self._accumulator = 0
end

function MovementService:_getState(player: Player): MoveState
	local state = self._states[player]
	if not state then
		state = {
			wantSprint = false,
			crouching = false,
			sprinting = false,
			stamina = self._config.MaxStamina,
			lastSprintEnd = 0,
			speedMultiplier = 1,
			humanoid = nil,
		}
		self._states[player] = state
	end
	return state
end

function MovementService:setSpeedMultiplier(player: Player, multiplier: number)
	local state = self._states[player]
	if state then
		state.speedMultiplier = math.max(0, multiplier)
	end
end

function MovementService:isSprinting(player: Player): boolean
	local state = self._states[player]
	return state ~= nil and state.sprinting
end

function MovementService:isCrouching(player: Player): boolean
	local state = self._states[player]
	return state ~= nil and state.crouching
end

function MovementService:_getWeight(player: Player): number
	local inventory = Registry.get("InventoryService")
	if not inventory then
		return 0
	end
	local ok, weight = pcall(function()
		return inventory:getTotalWeight(player)
	end)
	return (ok and type(weight) == "number") and weight or 0
end

function MovementService:_onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end

	local cfg = self._config
	local state = self:_getState(player)
	state.humanoid = humanoid
	state.stamina = cfg.MaxStamina
	state.sprinting = false
	state.wantSprint = false
	state.crouching = false
	state.speedMultiplier = 1
	state.lastSprintEnd = 0

	humanoid.UseJumpPower = true
	humanoid.JumpPower = cfg.JumpPower
	humanoid.WalkSpeed = cfg.BaseWalkSpeed

	player:SetAttribute("MaxStamina", cfg.MaxStamina)
	player:SetAttribute("Stamina", cfg.MaxStamina)
	player:SetAttribute("Sprinting", false)
	player:SetAttribute("Crouching", false)
	player:SetAttribute("HeavyWalk", false)
	player:SetAttribute("CarriedWeight", 0)
end

function MovementService:_updatePlayer(player: Player, dt: number)
	local cfg = self._config
	local state = self._states[player]
	if not state then
		return
	end
	local humanoid = state.humanoid
	if not humanoid or humanoid.Health <= 0 or not humanoid.Parent then
		return
	end

	-- Downed/dead players do not move. PlayerService owns that truth.
	local players = Registry.get("PlayerService")
	if players and not players:canMove(player) then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		state.sprinting = false
		return
	end

	local now = os.clock()
	local weight = self:_getWeight(player)
	local heavy = weight >= cfg.HeavyWalkThreshold
	local moving = humanoid.MoveDirection.Magnitude > 0.05

	local sprinting = false
	if state.wantSprint and not state.crouching then
		if state.sprinting then
			sprinting = state.stamina > 0
		else
			sprinting = state.stamina >= cfg.SprintMinStamina and moving
		end
	end
	state.sprinting = sprinting
	local sprintingActive = sprinting and moving

	if sprintingActive then
		local drain = cfg.SprintStaminaDrain * dt
		if heavy then
			drain *= cfg.HeavyStaminaDrainMultiplier
		end
		state.stamina = math.max(0, state.stamina - drain)
		state.lastSprintEnd = now
	elseif now - state.lastSprintEnd >= cfg.StaminaRegenDelay then
		state.stamina = math.min(cfg.MaxStamina, state.stamina + cfg.StaminaRegen * dt)
	end

	local base
	if state.crouching then
		base = cfg.CrouchSpeed
	elseif sprintingActive then
		base = cfg.SprintSpeed
	else
		base = cfg.BaseWalkSpeed
	end

	local over = math.max(0, weight - cfg.HeavyWalkThreshold)
	local speed = (base - over * cfg.SpeedPenaltyPerKg) * state.speedMultiplier
	speed = math.max(cfg.MinWalkSpeed, speed)

	humanoid.WalkSpeed = speed
	humanoid.JumpPower = state.crouching and cfg.CrouchJumpPower or cfg.JumpPower

	player:SetAttribute("Stamina", math.floor(state.stamina + 0.5))
	player:SetAttribute("Sprinting", sprintingActive)
	player:SetAttribute("Crouching", state.crouching)
	player:SetAttribute("HeavyWalk", heavy)
	player:SetAttribute("CarriedWeight", weight)
end

function MovementService:Start()
	local setSprint = Remotes.getEvent("Movement", "SetSprint")
	local setCrouch = Remotes.getEvent("Movement", "SetCrouch")

	setSprint.OnServerEvent:Connect(function(player, value)
		self:_getState(player).wantSprint = value == true
	end)
	setCrouch.OnServerEvent:Connect(function(player, value)
		self:_getState(player).crouching = value == true
	end)

	local function onPlayer(player: Player)
		self:_getState(player)
		player.CharacterAdded:Connect(function(character)
			self:_onCharacter(player, character)
		end)
		if player.Character then
			self:_onCharacter(player, player.Character)
		end
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		self._states[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		self._accumulator += dt
		if self._accumulator < self._config.UpdateInterval then
			return
		end
		local step = self._accumulator
		self._accumulator = 0
		for player in self._states do
			self:_updatePlayer(player, step)
		end
	end)

	log.info("online — walk/sprint/crouch/jump + stamina + weight->speed")
end

return MovementService
