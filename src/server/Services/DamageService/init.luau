--!strict
--[[
	DamageService (server-authoritative)
	------------------------------------
	THE single place damage is applied. Nothing else may touch Humanoid.Health
	for combat — weapons, explosions, vehicles and falls all route through
	:applyDamage, so every rule (armour, friendly fire, downed transitions,
	kill credit, XP, stats) is enforced exactly once.

	Pipeline for one hit:
	    resolve victim + zone  →  friendly-fire rule  →  body-part multiplier
	    →  armour absorption (ArmorService)  →  bleeding  →  health/state
	    transition (PlayerService)  →  credit + stats

	The client never reports damage; it only reports "I fired". Positions and
	hits come from the server's own ballistic trace.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)
local Data = require(Shared.Data)

local DamageService = {}
DamageService.Name = "DamageService"

local log = Logger.scope(DamageService.Name)

export type DamageInfo = {
	amount: number,
	zone: string?,
	attacker: Player?,
	weaponId: string?,
	ammoId: string?,
	penetration: number?,
	distance: number?,
	ignoreArmor: boolean?,
}

function DamageService:Init()
	self._config = Config.Combat
end

-- --- helpers ----------------------------------------------------------------

-- Walk up from a hit part to the Player that owns it (nil for world geometry).
function DamageService:resolvePlayer(instance: Instance?): (Player?, string?)
	if not instance then
		return nil, nil
	end
	local Players = game:GetService("Players")
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		local player = Players:GetPlayerFromCharacter(model)
		if player then
			return player, Data.BodyParts.zoneForPart(instance.Name)
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

function DamageService:_canDamage(attacker: Player?, victim: Player): (boolean, number)
	local players = Registry.expect("PlayerService")
	local state = players:getState(victim)

	if state.health == "Dead" then
		return false, 0
	end
	if not state.deployed then
		return false, 0 -- players in the menu are untouchable
	end
	if not attacker then
		return true, 1 -- environmental damage
	end
	if attacker == victim then
		return true, 1 -- self damage (own grenade) is always allowed
	end

	local factions = Registry.get("FactionService")
	if factions and factions:areAllies(attacker, victim) then
		local ff = self._config.FriendlyFireMultiplier
		return ff > 0, ff
	end
	return true, 1
end

-- --- the pipeline -----------------------------------------------------------

function DamageService:applyDamage(victim: Player, info: DamageInfo): number
	if info.amount <= 0 then
		return 0
	end

	local allowed, scale = self:_canDamage(info.attacker, victim)
	if not allowed then
		return 0
	end

	local players = Registry.expect("PlayerService")
	local state = players:getState(victim)
	local humanoid = state.humanoid
	if not humanoid or humanoid.Parent == nil then
		return 0
	end

	local zone = info.zone or "Chest"
	local zoneDef = Data.BodyParts.get(zone :: any)

	-- 1. body-part multiplier
	local damage = info.amount * zoneDef.multiplier * scale

	-- 2. armour
	-- Head is helmet-protected; Chest is plate-protected. Limbs are not.
	local absorbed = 0
	if not info.ignoreArmor and (zoneDef.armorable or zone == "Chest") then
		local armor = Registry.get("ArmorService")
		if armor then
			damage, absorbed = armor:absorb(victim, zone, damage, info.penetration)
		end
	end

	-- 3. bleeding from the wound
	if zoneDef.bleedRate > 0 and damage > 0 then
		players:addBleeding(victim, zoneDef.bleedRate * (damage / math.max(1, Config.Health.MaxHealth)))
	end

	state.lastDamageBy = info.attacker or state.lastDamageBy

	-- 4. health / state transition
	local lethalOutright = info.amount >= self._config.InstantDeathDamage

	if state.health == "Alive" then
		local remaining = humanoid.Health - damage
		if remaining > 0 and not lethalOutright then
			humanoid.Health = remaining
		elseif lethalOutright then
			players:kill(victim, info.attacker)
		else
			-- Downed, not dead. A critical-zone hit puts them straight into
			-- Critical instead of Wounded.
			players:down(victim, zoneDef.critical and zone == "Head")
		end
	else
		-- Already downed: further damage escalates, then finishes them.
		if state.health == "Wounded" then
			players:down(victim, true)
		else
			players:kill(victim, info.attacker)
		end
	end

	-- 5. feedback + credit
	if self._damageTaken then
		self._damageTaken:FireClient(victim, damage, zone, info.attacker)
	end
	if info.attacker and info.attacker ~= victim and self._hitMarker then
		self._hitMarker:FireClient(info.attacker, zone, damage, players:isDead(victim))
	end

	local data = Registry.get("DataService")
	if data and info.attacker then
		if players:isDead(victim) then
			data:incrementStat(info.attacker, "kills")
			data:incrementStat(victim, "deaths")
			local ranks = Registry.get("RankService")
			if ranks then
				-- XP is progression only; it never changes lethality.
				ranks:awardXp(info.attacker, zone == "Head" and 150 or 100)
			end
		end
	end

	return damage
end

-- Convenience for explosions / vehicle impacts: radial falloff, no zone.
function DamageService:applyRadial(origin: Vector3, radius: number, maxDamage: number, attacker: Player?)
	local Players = game:GetService("Players")
	local players = Registry.expect("PlayerService")
	for _, victim in Players:GetPlayers() do
		local state = players:getState(victim)
		local humanoid = state.humanoid
		local character = humanoid and humanoid.Parent
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local distance = (root.Position - origin).Magnitude
			if distance <= radius then
				local falloff = 1 - (distance / radius)
				self:applyDamage(victim, {
					amount = maxDamage * falloff,
					zone = "Chest",
					attacker = attacker,
					distance = distance,
					ignoreArmor = false,
				})
			end
		end
	end
end

function DamageService:Start()
	self._damageTaken = Remotes.getEvent("Combat", "DamageTaken")
	self._hitMarker = Remotes.getEvent("Combat", "HitMarker")
	log.info("online — single damage authority (zones, armour, transitions)")
end

return DamageService
