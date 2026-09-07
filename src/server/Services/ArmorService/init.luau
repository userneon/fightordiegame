--!strict
--[[
	ArmorService (server-authoritative)
	-----------------------------------
	Helmet and plate protection. Armour lives in the inventory as an equipped
	item with per-instance `state.durability`, so it is looted, worn and broken
	like any other object — this service owns the rules.

	Helmet behaviour (per spec):
	  - FIRST HEAD IMPACT: while a helmet is intact, the first round to strike
	    the head is guaranteed non-lethal — it is absorbed down to a survivable
	    value and the helmet takes the punishment instead. That is the moment
	    the helmet earns its weight.
	  - Subsequent impacts absorb only the normal fraction.
	  - Durability drains with absorbed damage; at 0 the piece is BROKEN and
	    protects nothing (state replicated so the HUD can show it).
	  - High-penetration rounds (Config.Armor.PenetrationBypass) defeat armour
	    outright — a helmet is not immortality.

	Returns how much damage actually reaches the player; DamageService applies it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Data = require(Shared.Data)

local ArmorService = {}
ArmorService.Name = "ArmorService"

local log = Logger.scope(ArmorService.Name)

-- Zone -> which equipped slot protects it.
local ZONE_SLOT = {
	Head = "Head",
	Chest = "Chest",
}

function ArmorService:Init()
	self._config = Config.Armor
	-- Tracks whether a player's helmet has already eaten its first head hit.
	self._firstImpactUsed = {} :: { [Player]: boolean }
end

-- --- state ------------------------------------------------------------------

function ArmorService:getPiece(player: Player, slot: string)
	local inventory = Registry.get("InventoryService")
	if not inventory then
		return nil
	end
	return inventory:getEquipped(player, slot)
end

function ArmorService:getDurability(player: Player, slot: string): number
	local stack = self:getPiece(player, slot)
	if not stack then
		return 0
	end
	local state = stack.state
	if state and type(state.durability) == "number" then
		return state.durability
	end
	local def = Data.Items.get(stack.itemId)
	return def and (def.props.durability or 0) or 0
end

function ArmorService:isBroken(player: Player, slot: string): boolean
	local stack = self:getPiece(player, slot)
	if not stack then
		return true
	end
	return self:getDurability(player, slot) <= 0
end

function ArmorService:_setDurability(player: Player, slot: string, value: number)
	local stack = self:getPiece(player, slot)
	if not stack then
		return
	end
	stack.state = stack.state or {}
	stack.state.durability = math.max(0, value)

	-- Replicate a compact view for the HUD.
	player:SetAttribute(slot .. "ArmorDurability", stack.state.durability)
	player:SetAttribute(slot .. "ArmorBroken", stack.state.durability <= 0)

	if stack.state.durability <= 0 then
		log.info(string.format("%s's %s armour is broken", player.Name, slot))
	end
end

-- --- absorption -------------------------------------------------------------

--[[
	Run incoming damage through armour.
	Returns: finalDamage, absorbedAmount
]]
function ArmorService:absorb(player: Player, zone: string, damage: number, penetration: number?): (number, number)
	local slot = ZONE_SLOT[zone]
	if not slot then
		return damage, 0 -- limbs/abdomen are unarmoured in this model
	end

	local stack = self:getPiece(player, slot)
	if not stack then
		return damage, 0
	end

	local durability = self:getDurability(player, slot)
	if durability <= 0 then
		return damage, 0 -- broken armour protects nothing
	end

	local cfg = self._config

	-- Armour-piercing rounds bypass armour entirely.
	if penetration and penetration >= cfg.PenetrationBypass then
		-- It still scuffs the plate on the way through.
		self:_setDurability(player, slot, durability - damage * 0.25)
		return damage, 0
	end

	local absorbFraction = slot == "Head" and cfg.HelmetAbsorb or cfg.PlateAbsorb
	local absorbed = damage * absorbFraction
	local through = damage - absorbed

	-- FIRST HEAD IMPACT: an intact helmet guarantees you survive the first one.
	if slot == "Head" and not self._firstImpactUsed[player] then
		self._firstImpactUsed[player] = true
		local players = Registry.get("PlayerService")
		local humanoid = players and players:getState(player).humanoid
		if humanoid then
			-- Leave at least 1 HP: the shot rings your bell, it does not kill.
			local survivable = math.max(0, humanoid.Health - 1)
			if through > survivable then
				absorbed += (through - survivable)
				through = survivable
			end
		end
		log.info(string.format("%s's helmet took the first head impact", player.Name))
	end

	self:_setDurability(player, slot, durability - absorbed * cfg.DurabilityPerDamage)
	return through, absorbed
end

-- Fresh character = fresh first-impact allowance.
function ArmorService:resetPlayer(player: Player)
	self._firstImpactUsed[player] = nil
	player:SetAttribute("HeadArmorBroken", false)
	player:SetAttribute("ChestArmorBroken", false)
end

function ArmorService:Start()
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		self._firstImpactUsed[player] = nil
	end)
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			self:resetPlayer(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)

	log.info("online — helmet/plate absorption, durability, first-impact rule")
end

return ArmorService
