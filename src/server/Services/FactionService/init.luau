--!strict
--[[
	FactionService (server-authoritative)
	-------------------------------------
	Owns faction assignment and the rules around changing it. The client may
	REQUEST a faction; only this service decides.

	Rules enforced here:
	  - Only playable factions may be requested (never Neutral).
	  - No switching while deployed/alive — you must be dead or still in the
	    menu, so a player cannot flip sides mid-firefight to dodge damage.
	  - Balance guard: cannot join a side that is already larger by more than
	    Config-driven tolerance.
	  - A switch cooldown blocks rapid flip-flopping.

	Faction data (spawn tags, respawn times, loot permissions, abilities) lives
	in Shared/Data/Factions — this service only applies it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)
local Data = require(Shared.Data)

local FactionService = {}
FactionService.Name = "FactionService"

local log = Logger.scope(FactionService.Name)

local SWITCH_COOLDOWN = 30 -- seconds between faction changes
local BALANCE_TOLERANCE = 2 -- how many players larger a side may already be

function FactionService:Init()
	self._lastSwitch = {} :: { [Player]: number }
end

-- --- queries ----------------------------------------------------------------

function FactionService:getFaction(player: Player): string
	local players = Registry.expect("PlayerService")
	return players:getState(player).faction
end

function FactionService:getDef(player: Player)
	return Data.Factions.get(self:getFaction(player))
end

function FactionService:areEnemies(a: Player, b: Player): boolean
	return Data.Factions.areEnemies(self:getFaction(a), self:getFaction(b))
end

function FactionService:areAllies(a: Player, b: Player): boolean
	local fa, fb = self:getFaction(a), self:getFaction(b)
	return fa == fb and Data.Factions.isPlayable(fa)
end

function FactionService:countFaction(faction: string): number
	local players = Registry.expect("PlayerService")
	local n = 0
	for _, player in Players:GetPlayers() do
		if players:getState(player).faction == faction then
			n += 1
		end
	end
	return n
end

-- Faction-wide ability gate (e.g. Eagle Eye is Army-only).
function FactionService:hasAbility(player: Player, ability: string): boolean
	local def = self:getDef(player)
	return def ~= nil and def.abilities[ability] == true
end

-- --- assignment -------------------------------------------------------------

-- Returns ok, reason. `force` skips player-facing rules (admin/auto-balance).
function FactionService:canJoin(player: Player, faction: string, force: boolean?): (boolean, string?)
	if not Data.Factions.isPlayable(faction) then
		return false, "not a playable faction"
	end
	if force then
		return true, nil
	end

	local players = Registry.expect("PlayerService")
	local state = players:getState(player)

	if state.faction == faction then
		return false, "already on that faction"
	end
	-- Cannot switch while in the fight; menu or dead only.
	if state.deployed and state.health ~= "Dead" then
		return false, "cannot switch faction while deployed"
	end

	local last = self._lastSwitch[player]
	if last and os.clock() - last < SWITCH_COOLDOWN then
		return false, "faction switch on cooldown"
	end

	-- Balance: block joining an already-dominant side.
	local other = faction == "Army" and "Terrorist" or "Army"
	if self:countFaction(faction) > self:countFaction(other) + BALANCE_TOLERANCE then
		return false, "that faction is full"
	end

	return true, nil
end

function FactionService:setFaction(player: Player, faction: string, force: boolean?): boolean
	local ok, reason = self:canJoin(player, faction, force)
	if not ok then
		log.info(string.format("%s denied faction '%s': %s", player.Name, faction, tostring(reason)))
		if self._changed then
			self._changed:FireClient(player, self:getFaction(player), reason)
		end
		return false
	end

	local players = Registry.expect("PlayerService")
	players:setFaction(player, faction)
	self._lastSwitch[player] = os.clock()

	-- Rank ladder differs per faction — reconcile the tier against the new one.
	local ranks = Registry.get("RankService")
	if ranks then
		ranks:refresh(player)
	end

	if self._changed then
		self._changed:FireClient(player, faction, nil)
	end
	log.info(string.format("%s joined %s", player.Name, faction))
	return true
end

-- Pick the smaller side; used when a player deploys without choosing.
function FactionService:autoAssign(player: Player): string
	local army = self:countFaction("Army")
	local terror = self:countFaction("Terrorist")
	local faction = army <= terror and "Army" or "Terrorist"
	self:setFaction(player, faction, true)
	return faction
end

function FactionService:Start()
	self._changed = Remotes.getEvent("Faction", "FactionChanged")
	local request = Remotes.getEvent("Faction", "RequestFaction")

	request.OnServerEvent:Connect(function(player, faction)
		if type(faction) ~= "string" then
			return
		end
		self:setFaction(player, faction)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._lastSwitch[player] = nil
	end)

	log.info("online — faction assignment + switch rules")
end

return FactionService
