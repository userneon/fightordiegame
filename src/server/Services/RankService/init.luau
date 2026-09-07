--!strict
--[[
	RankService (server-authoritative)
	----------------------------------
	Owns rank, XP and PERMISSIONS.

	Design rule (per spec): rank grants AUTHORITY and ACCESS — never damage or
	any other combat stat. Every gate in the game funnels through
	RankService:can(player, permission), so there is exactly one place that
	answers "is this player allowed to do that?".

	Permissions accumulate up the ladder: a Captain holds everything a Private,
	Corporal, Sergeant and Lieutenant hold, plus their own grants. The ladders
	themselves are data (Shared/Data/Ranks).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)
local Data = require(Shared.Data)

local RankService = {}
RankService.Name = "RankService"

local log = Logger.scope(RankService.Name)

function RankService:Init()
	-- Cache of resolved permission sets: [faction][tier] -> { [perm]: true }
	self._permCache = {} :: { [string]: { [number]: { [string]: boolean } } }
end

-- --- permission resolution --------------------------------------------------

function RankService:_permissionsFor(faction: string, tier: number): { [string]: boolean }
	local byFaction = self._permCache[faction]
	if not byFaction then
		byFaction = {}
		self._permCache[faction] = byFaction
	end
	local cached = byFaction[tier]
	if cached then
		return cached
	end

	-- Accumulate every grant from tier 1 up to this tier.
	local set: { [string]: boolean } = {}
	for _, rank in Data.Ranks.ladderFor(faction) do
		if rank.tier <= tier then
			for _, perm in rank.grants do
				set[perm] = true
			end
		end
	end
	byFaction[tier] = set
	return set
end

-- --- queries ----------------------------------------------------------------

function RankService:getTier(player: Player): number
	local players = Registry.expect("PlayerService")
	return players:getState(player).rankTier
end

function RankService:getRank(player: Player)
	local players = Registry.expect("PlayerService")
	local state = players:getState(player)
	return Data.Ranks.byTier(state.faction, state.rankTier)
end

function RankService:getTitle(player: Player): string
	local rank = self:getRank(player)
	return rank and rank.title or ""
end

-- THE authority gate. Every restricted action asks this.
function RankService:can(player: Player, permission: string): boolean
	local players = Registry.expect("PlayerService")
	local state = players:getState(player)
	return self:_permissionsFor(state.faction, state.rankTier)[permission] == true
end

-- Convenience for equipment/vehicle gating by raw tier.
function RankService:atLeastTier(player: Player, tier: number): boolean
	return self:getTier(player) >= tier
end

-- --- progression ------------------------------------------------------------

function RankService:getXp(player: Player): number
	local data = Registry.get("DataService")
	if not data then
		return 0
	end
	local profile = data:get(player)
	return profile and profile.xp or 0
end

-- Award XP and promote if a new tier is earned. Returns the new tier.
function RankService:awardXp(player: Player, amount: number): number
	if amount <= 0 then
		return self:getTier(player)
	end
	local data = Registry.get("DataService")
	local players = Registry.expect("PlayerService")
	local state = players:getState(player)

	local xp = 0
	if data then
		local profile = data:get(player)
		if profile then
			profile.xp += amount
			xp = profile.xp
		end
	end

	local newTier = Data.Ranks.tierForXp(state.faction, xp)
	if newTier > state.rankTier then
		self:setTier(player, newTier)
	end
	return state.rankTier
end

function RankService:setTier(player: Player, tier: number)
	local players = Registry.expect("PlayerService")
	local state = players:getState(player)
	local ladder = Data.Ranks.ladderFor(state.faction)
	local clamped = math.clamp(math.floor(tier), 1, #ladder)

	players:setRankTier(player, clamped)

	local data = Registry.get("DataService")
	if data then
		local profile = data:get(player)
		if profile then
			profile.rankTier = clamped
		end
	end

	local rank = Data.Ranks.byTier(state.faction, clamped)
	if self._changed then
		self._changed:FireClient(player, clamped, rank and rank.title or "")
	end
	log.info(string.format("%s is now %s", player.Name, rank and rank.title or tostring(clamped)))
end

-- Re-resolve the tier against the player's CURRENT faction ladder + XP. Called
-- after a faction switch so tiers never carry a stale ladder's permissions.
function RankService:refresh(player: Player)
	local players = Registry.expect("PlayerService")
	local state = players:getState(player)
	local tier = Data.Ranks.tierForXp(state.faction, self:getXp(player))
	self:setTier(player, math.max(tier, 1))
end

function RankService:Start()
	self._changed = Remotes.getEvent("Rank", "RankChanged")

	-- Promotion by a superior: requires the PromoteSquad permission, and you
	-- can never promote someone to your own tier or above.
	local requestPromote = Remotes.getEvent("Rank", "RequestPromote")
	requestPromote.OnServerEvent:Connect(function(player, targetPlayer)
		if typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") then
			return
		end
		if not self:can(player, Data.Ranks.Permissions.PromoteSquad) then
			return
		end
		local factions = Registry.expect("FactionService")
		if not factions:areAllies(player, targetPlayer) then
			return
		end
		local targetTier = self:getTier(targetPlayer)
		if targetTier + 1 >= self:getTier(player) then
			return -- cannot promote to your own rank or above
		end
		self:setTier(targetPlayer, targetTier + 1)
	end)

	log.info("online — rank authority + permissions (no combat bonuses)")
end

return RankService
