--!strict
--[[
	PlayerService (server-authoritative)
	------------------------------------
	Owns player lifecycle and the CHARACTER STATE MACHINE. Every other service
	asks this one "is this player alive / downed / able to fight?" — the answer
	lives in exactly one place.

	State machine
	-------------
	    Alive ──(damage kills)──▶ Wounded ──(more damage)──▶ Critical ──▶ Dead
	      ▲                          │                          │
	      └────── revive ────────────┴──────────────────────────┘

	  Alive    — normal.
	  Wounded  — downed, immobilised, bleeding, can be revived by a Medic.
	  Critical — downed and bleeding out ~CriticalBleedMultiplier faster.
	  Dead     — character killed; CorpseService takes over.

	Bleeding is a parallel numeric rate, not a state: you can bleed while Alive
	(a leg hit) and it ticks damage until bandaged.

	Replicated as Player attributes (HUD / client read-only):
	  Faction, Role, RankTier, RankTitle, HealthState, Bleeding, Deployed
	Nothing here trusts the client — all transitions are server-driven.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)
local Data = require(Shared.Data)

local PlayerService = {}
PlayerService.Name = "PlayerService"

local log = Logger.scope(PlayerService.Name)

export type State = {
	faction: string,
	role: string,
	rankTier: number,
	health: string, -- "Alive" | "Wounded" | "Critical" | "Dead"
	bleeding: number,
	deployed: boolean,
	downedAt: number?,
	lastDamageBy: Player?,
	humanoid: Humanoid?,
}

function PlayerService:Init()
	self._config = Config.Health
	self._combat = Config.Combat
	self._states = {} :: { [Player]: State }
	self._accumulator = 0
end

-- --- state access -----------------------------------------------------------

function PlayerService:getState(player: Player): State
	local state = self._states[player]
	if not state then
		state = {
			faction = "Neutral",
			role = Data.Roles.Default,
			rankTier = 1,
			health = "Alive",
			bleeding = 0,
			deployed = false,
			downedAt = nil,
			lastDamageBy = nil,
			humanoid = nil,
		}
		self._states[player] = state
	end
	return state
end

function PlayerService:isAlive(player: Player): boolean
	return self:getState(player).health == "Alive"
end

function PlayerService:isDowned(player: Player): boolean
	local h = self:getState(player).health
	return h == "Wounded" or h == "Critical"
end

function PlayerService:isDead(player: Player): boolean
	return self:getState(player).health == "Dead"
end

-- Downed players cannot shoot, carry, drive or interact.
function PlayerService:canFight(player: Player): boolean
	local state = self:getState(player)
	return state.deployed and state.health == "Alive"
end

function PlayerService:canMove(player: Player): boolean
	return self:getState(player).health == "Alive"
end

-- --- replication ------------------------------------------------------------

function PlayerService:_publish(player: Player)
	local state = self:getState(player)
	player:SetAttribute("Faction", state.faction)
	player:SetAttribute("Role", state.role)
	player:SetAttribute("RankTier", state.rankTier)
	player:SetAttribute("HealthState", state.health)
	player:SetAttribute("Bleeding", state.bleeding)
	player:SetAttribute("Deployed", state.deployed)

	local rank = Data.Ranks.byTier(state.faction, state.rankTier)
	player:SetAttribute("RankTitle", rank and rank.title or "")

	if self._stateChanged then
		self._stateChanged:FireAllClients(player, state.health, state.bleeding)
	end
end

-- Public setters used by Faction/Rank/Game services (they own the RULES,
-- this service owns the STORAGE + replication).
function PlayerService:setFaction(player: Player, faction: string)
	self:getState(player).faction = faction
	self:_publish(player)
end

function PlayerService:setRole(player: Player, role: string)
	self:getState(player).role = role
	self:_publish(player)
end

function PlayerService:setRankTier(player: Player, tier: number)
	self:getState(player).rankTier = tier
	self:_publish(player)
end

function PlayerService:setDeployed(player: Player, deployed: boolean)
	self:getState(player).deployed = deployed
	self:_publish(player)
end

-- --- transitions ------------------------------------------------------------

function PlayerService:_setHealthState(player: Player, health: string)
	local state = self:getState(player)
	if state.health == health then
		return
	end
	state.health = health
	if health == "Wounded" or health == "Critical" then
		state.downedAt = state.downedAt or os.clock()
	elseif health == "Alive" then
		state.downedAt = nil
	end
	self:_publish(player)
	log.info(string.format("%s -> %s", player.Name, health))
end

-- Immobilise/restore the character to match the state.
function PlayerService:_applyMobility(player: Player)
	local state = self:getState(player)
	local humanoid = state.humanoid
	if not humanoid or humanoid.Parent == nil then
		return
	end
	if state.health == "Wounded" or state.health == "Critical" then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end
	-- When Alive, MovementService owns WalkSpeed again (it checks canMove).
end

-- Put a player down (not dead). Called by DamageService.
function PlayerService:down(player: Player, critical: boolean?)
	local state = self:getState(player)
	if state.health == "Dead" then
		return
	end
	local target = critical and "Critical" or "Wounded"
	-- Downing an already-wounded player escalates to Critical.
	if state.health == "Wounded" and not critical then
		target = "Critical"
	end
	self:_setHealthState(player, target)

	local humanoid = state.humanoid
	if humanoid and humanoid.Parent then
		-- Keep the character technically alive so it stays in the world.
		humanoid.Health = math.max(1, humanoid.Health)
	end
	self:_applyMobility(player)
end

function PlayerService:kill(player: Player, killer: Player?)
	local state = self:getState(player)
	if state.health == "Dead" then
		return
	end
	state.lastDamageBy = killer or state.lastDamageBy
	self:_setHealthState(player, "Dead")
	state.bleeding = 0

	-- Hand the body to CorpseService BEFORE the humanoid dies so it can copy
	-- inventory/position while everything still exists.
	local corpses = Registry.get("CorpseService")
	if corpses then
		local ok, err = pcall(function()
			corpses:createFromPlayer(player)
		end)
		if not ok then
			log.error("corpse creation failed:", tostring(err))
		end
	end

	local humanoid = state.humanoid
	if humanoid and humanoid.Parent and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

function PlayerService:revive(player: Player, health: number?)
	local state = self:getState(player)
	if state.health ~= "Wounded" and state.health ~= "Critical" then
		return false
	end
	self:_setHealthState(player, "Alive")
	state.bleeding = 0
	state.downedAt = nil

	local humanoid = state.humanoid
	if humanoid and humanoid.Parent then
		humanoid.Health = math.clamp(health or self._config.ReviveHealth, 1, humanoid.MaxHealth)
	end
	self:_publish(player)
	return true
end

function PlayerService:heal(player: Player, amount: number)
	local state = self:getState(player)
	local humanoid = state.humanoid
	if not humanoid or humanoid.Parent == nil or state.health == "Dead" then
		return
	end
	humanoid.Health = math.clamp(humanoid.Health + amount, 0, humanoid.MaxHealth)
end

-- Bleeding is additive; bandages clear it.
function PlayerService:addBleeding(player: Player, rate: number)
	local state = self:getState(player)
	state.bleeding = math.max(0, state.bleeding + rate)
	self:_publish(player)
end

function PlayerService:stopBleeding(player: Player)
	local state = self:getState(player)
	if state.bleeding == 0 then
		return
	end
	state.bleeding = 0
	self:_publish(player)
end

-- --- bleed / bleed-out loop -------------------------------------------------

function PlayerService:_tick(dt: number)
	local cfg = self._config
	local combat = self._combat
	local now = os.clock()

	for player, state in self._states do
		if state.health ~= "Dead" and state.deployed then
			-- Bleed damage.
			if state.bleeding > 0 then
				local humanoid = state.humanoid
				if humanoid and humanoid.Parent and state.health == "Alive" then
					local loss = state.bleeding * cfg.BleedDamagePerTick * dt
					if humanoid.Health - loss <= 0 then
						self:down(player)
					else
						humanoid.Health -= loss
					end
				end
				if self._bleedTick then
					self._bleedTick:FireClient(player, state.bleeding)
				end
			end

			-- Bleed-out while downed.
			if state.downedAt and (state.health == "Wounded" or state.health == "Critical") then
				local limit = cfg.BleedOutTime
				if state.health == "Critical" then
					limit /= math.max(1, combat.CriticalBleedMultiplier)
				end
				if now - state.downedAt >= limit then
					self:kill(player, state.lastDamageBy)
				end
			end
		end
	end
end

-- --- lifecycle --------------------------------------------------------------

function PlayerService:_onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	local state = self:getState(player)
	state.humanoid = humanoid
	state.bleeding = 0
	state.downedAt = nil
	humanoid.MaxHealth = self._config.MaxHealth
	humanoid.Health = self._config.MaxHealth
	self:_setHealthState(player, "Alive")

	-- Fallback: anything that kills the humanoid outside DamageService (void,
	-- crushing, fall) still resolves to a proper Dead transition.
	humanoid.Died:Connect(function()
		self:kill(player, state.lastDamageBy)
	end)
end

function PlayerService:_onPlayerAdded(player: Player)
	self:getState(player)
	self:_publish(player)
	player.CharacterAdded:Connect(function(character)
		self:_onCharacter(player, character)
	end)
	if player.Character then
		self:_onCharacter(player, player.Character)
	end
end

function PlayerService:Start()
	self._stateChanged = Remotes.getEvent("Player", "StateChanged")
	self._bleedTick = Remotes.getEvent("Wounded", "BleedTick")

	for _, player in Players:GetPlayers() do
		self:_onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self._states[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		self._accumulator += dt
		if self._accumulator < self._config.BleedTickInterval then
			return
		end
		local step = self._accumulator
		self._accumulator = 0
		self:_tick(step)
	end)

	log.info("online — character state machine (Alive/Wounded/Critical/Dead)")
end

return PlayerService
