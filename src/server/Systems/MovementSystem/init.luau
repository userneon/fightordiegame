--!strict
--[[
	MovementSystem (server-authoritative)
	-------------------------------------
	Owns the character movement model for FIGHT OR DIE:
	  - Walk / Sprint / Crouch speeds
	  - Jump tuning (JumpPower, disabled while crouched)
	  - Stamina (sprinting drains it, it regenerates when you stop)
	  - Heavy Walk state driven by carried weight
	  - Inventory-weight -> speed penalty (reads InventorySystem)

	Authority model
	---------------
	In Roblox the character's own client simulates physics, but Humanoid
	properties set on the SERVER replicate down and are the shared source of
	truth. So the server owns WalkSpeed / JumpPower here; clients only send
	*intent* (sprint held? crouch held?) via Remotes.Movement. A cheater can
	still poke their local Humanoid, so treat this as authoritative-by-default,
	not anti-cheat-complete — server-side validation can be layered on later.

	Replicated state (as Player attributes, for the HUD / animations to read):
	  Stamina, MaxStamina, Sprinting, Crouching, HeavyWalk, CarriedWeight

	Other systems
	-------------
	CarrySystem etc. can call MovementSystem:setSpeedMultiplier(player, m) to
	apply a temporary multiplier (e.g. slow the carrier) without fighting this
	loop over WalkSpeed.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Remotes = require(Shared.Remotes)

-- Cross-system reference (ModuleScripts are singletons, so this is the same
-- InventorySystem instance the bootstrap loads). No circular dependency:
-- InventorySystem does not require MovementSystem.
local InventorySystem = require(script.Parent.InventorySystem)

local MovementSystem = {}
MovementSystem.Name = "MovementSystem"

local log = Logger.scope(MovementSystem.Name)

type PlayerState = {
	wantSprint: boolean,
	crouching: boolean,
	sprinting: boolean, -- resolved (intent + gating)
	stamina: number,
	lastSprintEnd: number, -- os.clock() when sprint last stopped, for regen delay
	speedMultiplier: number, -- external hook (carry, effects, etc.)
	humanoid: Humanoid?,
}

function MovementSystem:Init()
	self._config = Config.Movement
	self._states = {} :: { [Player]: PlayerState }
	self._accumulator = 0
end

-- --- state helpers ---------------------------------------------------------

function MovementSystem:_getState(player: Player): PlayerState
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

-- Public hook for other systems (e.g. CarrySystem) to slow/speed a player.
function MovementSystem:setSpeedMultiplier(player: Player, multiplier: number)
	local state = self._states[player]
	if state then
		state.speedMultiplier = math.max(0, multiplier)
	end
end

-- --- weight ----------------------------------------------------------------

function MovementSystem:_getWeight(player: Player): number
	-- Guarded: InventorySystem may not have real data yet.
	local ok, weight = pcall(function()
		return InventorySystem:getTotalWeight(player)
	end)
	if ok and type(weight) == "number" then
		return weight
	end
	return 0
end

-- --- character setup -------------------------------------------------------

function MovementSystem:_onCharacter(player: Player, character: Model)
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

	-- Use JumpPower so we can tune/disable it (crouch).
	humanoid.UseJumpPower = true
	humanoid.JumpPower = cfg.JumpPower
	humanoid.WalkSpeed = cfg.BaseWalkSpeed

	player:SetAttribute("MaxStamina", cfg.MaxStamina)
	player:SetAttribute("Stamina", cfg.MaxStamina)
	player:SetAttribute("Sprinting", false)
	player:SetAttribute("Crouching", false)
	player:SetAttribute("HeavyWalk", false)
	player:SetAttribute("CarriedWeight", 0)

	humanoid.Died:Connect(function()
		state.sprinting = false
		state.wantSprint = false
		state.crouching = false
	end)
end

function MovementSystem:_onPlayerAdded(player: Player)
	self:_getState(player)
	if player.Character then
		self:_onCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		self:_onCharacter(player, character)
	end)
end

-- --- per-frame update ------------------------------------------------------

function MovementSystem:_updatePlayer(player: Player, dt: number)
	local cfg = self._config
	local state = self._states[player]
	if not state then
		return
	end

	local humanoid = state.humanoid
	if not humanoid or humanoid.Health <= 0 or not humanoid.Parent then
		return
	end

	local now = os.clock()
	local weight = self:_getWeight(player)
	local heavy = weight >= cfg.HeavyWalkThreshold
	local moving = humanoid.MoveDirection.Magnitude > 0.05

	-- Resolve sprint intent into actual sprinting.
	local sprinting = false
	if state.wantSprint and not state.crouching then
		if state.sprinting then
			-- keep sprinting until stamina is fully drained
			sprinting = state.stamina > 0
		else
			-- need a minimum reserve (and to be moving) to *start*
			sprinting = state.stamina >= cfg.SprintMinStamina and moving
		end
	end
	state.sprinting = sprinting

	local sprintingActive = sprinting and moving

	-- Stamina drain / regen.
	if sprintingActive then
		local drain = cfg.SprintStaminaDrain * dt
		if heavy then
			drain *= cfg.HeavyStaminaDrainMultiplier
		end
		state.stamina = math.max(0, state.stamina - drain)
		state.lastSprintEnd = now
	else
		if now - state.lastSprintEnd >= cfg.StaminaRegenDelay then
			state.stamina = math.min(cfg.MaxStamina, state.stamina + cfg.StaminaRegen * dt)
		end
	end

	-- Base speed by stance.
	local base
	if state.crouching then
		base = cfg.CrouchSpeed
	elseif sprintingActive then
		base = cfg.SprintSpeed
	else
		base = cfg.BaseWalkSpeed
	end

	-- Weight penalty (only past the Heavy threshold).
	local over = math.max(0, weight - cfg.HeavyWalkThreshold)
	local penalty = over * cfg.SpeedPenaltyPerKg
	local speed = (base - penalty) * state.speedMultiplier
	speed = math.max(cfg.MinWalkSpeed, speed)

	humanoid.WalkSpeed = speed
	humanoid.JumpPower = state.crouching and cfg.CrouchJumpPower or cfg.JumpPower

	-- Replicate state for HUD / animations (attributes no-op when unchanged).
	player:SetAttribute("Stamina", math.floor(state.stamina + 0.5))
	player:SetAttribute("Sprinting", sprintingActive)
	player:SetAttribute("Crouching", state.crouching)
	player:SetAttribute("HeavyWalk", heavy)
	player:SetAttribute("CarriedWeight", weight)
end

-- --- lifecycle -------------------------------------------------------------

function MovementSystem:Start()
	-- Remotes: client intent.
	local setSprint = Remotes.getEvent("Movement", "SetSprint")
	local setCrouch = Remotes.getEvent("Movement", "SetCrouch")

	setSprint.OnServerEvent:Connect(function(player, value)
		local state = self:_getState(player)
		state.wantSprint = value == true
	end)

	setCrouch.OnServerEvent:Connect(function(player, value)
		local state = self:_getState(player)
		state.crouching = value == true
	end)

	-- Players.
	for _, player in Players:GetPlayers() do
		self:_onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self._states[player] = nil
	end)

	-- Throttled update loop.
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

	log.info("online — walk/sprint/crouch/jump + stamina + weight->speed active")
end

return MovementSystem
